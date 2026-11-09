import Foundation
import CryptoKit

/// One Demucs checkpoint file. The part of the name after the dash is the SHA-256 prefix
/// that Demucs/torch use to verify it.
struct ModelFile: Hashable {
    let name: String
    let size: Int64
    var url: URL { URL(string: "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/\(name).th")! }
    var hashPrefix: String { String(name.split(separator: "-").last ?? "") }
}

struct ModelConfig: Identifiable, Hashable {
    let id: String          // Demucs model name, passed to `demucs -n`
    let label: String
    let detail: String
    let icon: String
    let files: [ModelFile]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    static let all: [ModelConfig] = [
        ModelConfig(
            id: "htdemucs", label: "Standard",
            detail: "Vocals, drums, bass and other. Fast, and the best place to start.",
            icon: "waveform",
            files: [ModelFile(name: "955717e8-8726e21a", size: 84_141_911)]),
        ModelConfig(
            id: "htdemucs_ft", label: "High quality",
            detail: "Same four stems, cleaner results. About four times slower.",
            icon: "sparkles",
            files: [
                ModelFile(name: "f7e0c4bc-ba3fe64a", size: 84_141_271),
                ModelFile(name: "d12395a8-e57c48e6", size: 84_141_271),
                ModelFile(name: "92cfc3b6-ef3bcb9c", size: 84_141_271),
                ModelFile(name: "04573f0d-f3cf25b2", size: 84_141_271),
            ]),
        ModelConfig(
            id: "htdemucs_6s", label: "Six stems",
            detail: "Adds guitar and piano. Piano is the weakest of the six.",
            icon: "guitars",
            files: [ModelFile(name: "5c90dfd2-34c22ccb", size: 54_996_327)]),
    ]
}

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

@MainActor
final class ModelStore: ObservableObject {
    struct DownloadState {
        var fraction: Double = 0
        var error: String?
        var active = false
    }

    @Published private(set) var installed: Set<String> = []
    @Published private(set) var demucsPath: String?
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var isDownloading = false
    /// False until the user has demucs and at least one model; gates the first-run screen.
    @Published var setupComplete = false

    private var downloadTask: Task<Void, Never>?

    /// Where torch (and therefore Demucs) looks for checkpoints. STEMSEP_CHECKPOINTS_DIR is a test hook.
    static var checkpointsDir: URL {
        if let o = ProcessInfo.processInfo.environment["STEMSEP_CHECKPOINTS_DIR"] {
            return URL(fileURLWithPath: o)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/torch/hub/checkpoints")
    }

    init() {
        refresh()
        let force = ProcessInfo.processInfo.environment["STEMSEP_FORCE_SETUP"] != nil
        setupComplete = !force && demucsPath != nil && !installed.isEmpty
    }

    func refresh() {
        demucsPath = Self.findDemucs()
        installed = Set(ModelConfig.all.filter(Self.isInstalled).map(\.id))
    }

    static func isInstalled(_ m: ModelConfig) -> Bool {
        m.files.allSatisfy { f in
            let path = checkpointsDir.appendingPathComponent(f.name + ".th").path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
            return (size ?? 0) > 1_000_000
        }
    }

    static func findDemucs() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(home)/.local/bin"]
        let fw = "/Library/Frameworks/Python.framework/Versions"
        for v in ((try? fm.contentsOfDirectory(atPath: fw)) ?? []).sorted(by: >) { dirs.append("\(fw)/\(v)/bin") }
        let user = "\(home)/Library/Python"
        for v in ((try? fm.contentsOfDirectory(atPath: user)) ?? []).sorted(by: >) { dirs.append("\(user)/\(v)/bin") }
        return dirs.map { $0 + "/demucs" }.first { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: Downloading

    func startDownload(_ models: [ModelConfig]) {
        guard downloadTask == nil else { return }
        let todo = models.filter { !installed.contains($0.id) }
        guard !todo.isEmpty else { return }
        isDownloading = true
        for m in todo { downloads[m.id] = DownloadState(active: true) }
        downloadTask = Task { [weak self] in
            for m in todo {
                if Task.isCancelled { break }
                await self?.download(m)
            }
            self?.finishDownloads()
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    private func finishDownloads() {
        downloadTask = nil
        isDownloading = false
        refresh()
    }

    private func download(_ m: ModelConfig) async {
        let dir = Self.checkpointsDir
        var finished: Int64 = 0
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in m.files {
                let dest = dir.appendingPathComponent(f.name + ".th")
                if FileManager.default.fileExists(atPath: dest.path) { finished += f.size; continue }
                let part = dest.appendingPathExtension("part")
                let base = finished
                let total = Double(m.totalBytes)
                try await FileDownloader().download(f.url, to: part) { [weak self] bytes in
                    Task { @MainActor in
                        self?.downloads[m.id]?.fraction = min(1, Double(base + bytes) / total)
                    }
                }
                let prefix = f.hashPrefix
                try await Task.detached { try Self.verify(part, prefix: prefix) }.value
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: part, to: dest)
                finished += f.size
            }
            downloads[m.id] = DownloadState(fraction: 1)
        } catch {
            for f in m.files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f.name + ".th.part"))
            }
            let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            downloads[m.id] = cancelled ? DownloadState() : DownloadState(error: error.localizedDescription)
        }
        refresh()
    }

    nonisolated static func verify(_ url: URL, prefix: String) throws {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var sha = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { sha.update(data: chunk) }
        let hex = sha.finalize().map { String(format: "%02x", $0) }.joined()
        guard hex.hasPrefix(prefix) else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: "StemSeparator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The downloaded file was corrupted. Please try again."])
        }
    }
}

/// Downloads one file to disk with throttled byte-count progress.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var dest: URL!
    private var onProgress: (@Sendable (Int64) -> Void)?
    private var lastReport = Date.distantPast
    private var task: URLSessionDownloadTask?

    func download(_ url: URL, to dest: URL, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        self.dest = dest
        self.onProgress = onProgress
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.continuation = cont
                let t = session.downloadTask(with: url)
                self.task = t
                t.resume()
                if Task.isCancelled { t.cancel() }
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite _: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        onProgress?(written)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(NSError(domain: "StemSeparator", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "The server returned HTTP \(http.statusCode)."])))
            return
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            onProgress?(downloadTask.countOfBytesReceived)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

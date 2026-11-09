import Foundation
import CryptoKit

/// Which command-line tool runs a model.
enum Engine: String {
    case demucs
    case audioSeparator

    var toolName: String { self == .demucs ? "demucs" : "audio-separator" }
    var installCommand: String {
        self == .demucs ? "pip3 install demucs" : "pip3 install \"audio-separator[cpu]\""
    }
}

/// One file a model needs on disk. `urls` are tried in order.
/// `size` 0 means "small support file; any non-empty file counts as present".
struct ModelFile: Hashable {
    let name: String
    let size: Int64
    let urls: [URL]
    var sha256: String? = nil        // full SHA-256 of the file
    var sha256Prefix: String? = nil  // Demucs/torch style: prefix only

    /// A Demucs checkpoint. The part of the name after the dash is its SHA-256 prefix.
    static func demucs(_ id: String, size: Int64) -> ModelFile {
        ModelFile(
            name: id + ".th", size: size,
            urls: [URL(string: "https://dl.fbaipublicfiles.com/demucs/hybrid_transformer/\(id).th")!],
            sha256Prefix: String(id.split(separator: "-").last ?? ""))
    }
}

struct ModelConfig: Identifiable, Hashable {
    let id: String          // Demucs model name (`demucs -n`), or the UVR model file name
    let label: String
    let detail: String
    let icon: String
    let engine: Engine
    let files: [ModelFile]
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Demucs keeps checkpoints where torch does; audio-separator models live in the app's own folder.
    var directory: URL {
        engine == .demucs ? ModelStore.checkpointsDir : ModelStore.separatorModelsDir
    }

    static let wind = "17_HP-Wind_Inst-UVR.pth"

    static let all: [ModelConfig] = [
        ModelConfig(
            id: "htdemucs", label: "Standard",
            detail: "Vocals, drums, bass and other. Fast, and the best place to start.",
            icon: "waveform", engine: .demucs,
            files: [.demucs("955717e8-8726e21a", size: 84_141_911)]),
        ModelConfig(
            id: "htdemucs_ft", label: "High quality",
            detail: "Same four stems, cleaner results. About four times slower.",
            icon: "sparkles", engine: .demucs,
            files: [
                .demucs("f7e0c4bc-ba3fe64a", size: 84_141_271),
                .demucs("d12395a8-e57c48e6", size: 84_141_271),
                .demucs("92cfc3b6-ef3bcb9c", size: 84_141_271),
                .demucs("04573f0d-f3cf25b2", size: 84_141_271),
            ]),
        ModelConfig(
            id: "htdemucs_6s", label: "Six stems",
            detail: "Adds guitar and piano. Piano is the weakest of the six.",
            icon: "guitars", engine: .demucs,
            files: [.demucs("5c90dfd2-34c22ccb", size: 54_996_327)]),
        ModelConfig(
            id: wind, label: "Woodwinds",
            detail: "Splits out saxophone, flute, clarinet and other woodwinds, and leaves everything else in the track. Needs audio-separator.",
            icon: "music.quarternote.3", engine: .audioSeparator,
            files: [
                ModelFile(
                    name: wind, size: 223_661_285,
                    urls: [
                        URL(string: "https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/\(wind)")!,
                        URL(string: "https://github.com/nomadkaraoke/python-audio-separator/releases/download/model-configs/\(wind)")!,
                    ],
                    sha256: "acc6d472b4b478da9c9ab5af45b167749e05a7f65b30c7d5988b3700a513aeee"),
                // Metadata audio-separator looks up on every run; fetching it now makes the model work offline.
                ModelFile(name: "download_checks.json", size: 0, urls: [
                    URL(string: "https://raw.githubusercontent.com/TRvlvr/application_data/main/filelists/download_checks.json")!]),
                ModelFile(name: "vr_model_data.json", size: 0, urls: [
                    URL(string: "https://raw.githubusercontent.com/TRvlvr/application_data/main/vr_model_data/model_data_new.json")!]),
                ModelFile(name: "mdx_model_data.json", size: 0, urls: [
                    URL(string: "https://raw.githubusercontent.com/TRvlvr/application_data/main/mdx_model_data/model_data_new.json")!]),
            ]),
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
    @Published private(set) var toolPaths: [Engine: String] = [:]
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var isDownloading = false
    /// False until at least one model can actually run; gates the first-run screen.
    @Published var setupComplete = false

    private var downloadTask: Task<Void, Never>?

    /// Where torch (and therefore Demucs) looks for checkpoints. STEMSEP_CHECKPOINTS_DIR is a test hook.
    nonisolated static var checkpointsDir: URL {
        if let o = ProcessInfo.processInfo.environment["STEMSEP_CHECKPOINTS_DIR"] {
            return URL(fileURLWithPath: o)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/torch/hub/checkpoints")
    }

    /// Models for audio-separator. STEMSEP_MODELS_DIR is a test hook.
    nonisolated static var separatorModelsDir: URL {
        if let o = ProcessInfo.processInfo.environment["STEMSEP_MODELS_DIR"] {
            return URL(fileURLWithPath: o)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/StemSeparator/models")
    }

    init() {
        refresh()
        let force = ProcessInfo.processInfo.environment["STEMSEP_FORCE_SETUP"] != nil
        setupComplete = !force && ModelConfig.all.contains(where: usable)
    }

    func toolPath(for engine: Engine) -> String? { toolPaths[engine] }

    /// Installed and its tool is present, so it can run right now.
    func usable(_ m: ModelConfig) -> Bool { installed.contains(m.id) && toolPaths[m.engine] != nil }

    func refresh() {
        for e in [Engine.demucs, .audioSeparator] { toolPaths[e] = Self.findTool(e) }
        installed = Set(ModelConfig.all.filter(Self.isInstalled).map(\.id))
    }

    static func isInstalled(_ m: ModelConfig) -> Bool {
        m.files.allSatisfy { hasFile($0, in: m.directory) }
    }

    static func hasFile(_ f: ModelFile, in dir: URL) -> Bool {
        let path = dir.appendingPathComponent(f.name).path
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        else { return false }
        return f.size == 0 ? size > 0 : size >= f.size
    }

    /// STEMSEP_AUDIO_SEPARATOR is a test hook.
    static func findTool(_ engine: Engine) -> String? {
        let fm = FileManager.default
        if engine == .audioSeparator,
           let o = ProcessInfo.processInfo.environment["STEMSEP_AUDIO_SEPARATOR"], fm.isExecutableFile(atPath: o) {
            return o
        }
        let home = NSHomeDirectory()
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(home)/.local/bin"]
        let fw = "/Library/Frameworks/Python.framework/Versions"
        for v in ((try? fm.contentsOfDirectory(atPath: fw)) ?? []).sorted(by: >) { dirs.append("\(fw)/\(v)/bin") }
        let user = "\(home)/Library/Python"
        for v in ((try? fm.contentsOfDirectory(atPath: user)) ?? []).sorted(by: >) { dirs.append("\(user)/\(v)/bin") }
        return dirs.map { $0 + "/" + engine.toolName }.first { fm.isExecutableFile(atPath: $0) }
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
        let dir = m.directory
        var finished: Int64 = 0
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in m.files {
                let dest = dir.appendingPathComponent(f.name)
                if Self.hasFile(f, in: dir) { finished += f.size; continue }
                let part = dest.appendingPathExtension("part")
                let base = finished
                let total = Double(max(m.totalBytes, 1))
                try await Self.fetch(f, to: part) { [weak self] bytes in
                    Task { @MainActor in
                        self?.downloads[m.id]?.fraction = min(1, Double(base + bytes) / total)
                    }
                }
                try await Task.detached { try Self.verify(part, for: f) }.value
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: part, to: dest)
                finished += f.size
            }
            downloads[m.id] = DownloadState(fraction: 1)
        } catch {
            for f in m.files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(f.name + ".part"))
            }
            let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            downloads[m.id] = cancelled ? DownloadState() : DownloadState(error: error.localizedDescription)
        }
        refresh()
    }

    /// Tries each URL in turn; a cancel stops immediately, any other failure moves to the next source.
    private static func fetch(_ f: ModelFile, to part: URL,
                              onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        var lastError: Error = URLError(.badURL)
        for url in f.urls {
            do {
                try await FileDownloader().download(url, to: part, onProgress: onProgress)
                return
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    nonisolated static func verify(_ url: URL, for f: ModelFile) throws {
        guard f.sha256 != nil || f.sha256Prefix != nil else { return }
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var sha = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { sha.update(data: chunk) }
        let hex = sha.finalize().map { String(format: "%02x", $0) }.joined()
        let ok = f.sha256.map { hex == $0 } ?? f.sha256Prefix.map { hex.hasPrefix($0) } ?? true
        guard ok else {
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

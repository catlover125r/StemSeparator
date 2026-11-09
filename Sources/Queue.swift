import Foundation
import AppKit

struct StemOutput: Identifiable {
    let id = UUID()
    let stem: String        // "vocals", "drums", "no_vocals", "Woodwinds", ...
    let url: URL
    var label: String {
        switch stem {
        case "no_vocals": return "Instrumental"
        default: return stem.prefix(1).uppercased() + stem.dropFirst()
        }
    }
}

@MainActor
final class QueueItem: ObservableObject, Identifiable {
    enum Status: Equatable { case waiting, running, done, failed(String) }

    let id = UUID()
    let url: URL
    let model: ModelConfig
    let twoStems: Bool
    @Published var status: Status = .waiting
    @Published var progress: Double = 0
    @Published var stems: [StemOutput] = []
    fileprivate var process: Process?
    fileprivate var cancelled = false

    var title: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL, model: ModelConfig, twoStems: Bool) {
        self.url = url
        self.model = model
        self.twoStems = twoStems
    }
}

@MainActor
final class QueueManager: ObservableObject {
    @Published private(set) var items: [QueueItem] = []
    private var worker: Task<Void, Never>?

    static let audioExts: Set<String> = ["mp3", "wav", "flac", "m4a", "aac", "ogg", "aiff", "aif", "caf", "mp4"]
    static let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StemSeparator")

    init() {
        try? FileManager.default.removeItem(at: Self.cacheRoot)   // stems from earlier sessions
    }

    func add(_ urls: [URL], model: ModelConfig, twoStems: Bool, tool: String?) {
        for u in urls where Self.audioExts.contains(u.pathExtension.lowercased()) {
            items.append(QueueItem(url: u, model: model, twoStems: twoStems))
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = self.items.first(where: { $0.status == .waiting }) {
                await self.run(next, tool: tool)
            }
            self?.worker = nil
        }
    }

    func remove(_ item: QueueItem) {
        item.cancelled = true
        item.process?.terminate()
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: Self.cacheRoot.appendingPathComponent(item.id.uuidString))
    }

    private func run(_ item: QueueItem, tool: String?) async {
        let engine = item.model.engine
        guard let tool else {
            item.status = .failed("\(engine.toolName) not found.\nInstall with: \(engine.installCommand)")
            return
        }
        item.status = .running
        let out = Self.cacheRoot.appendingPathComponent(item.id.uuidString)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Demucs runs on the Apple GPU (mps) first and falls back to the CPU if that fails.
        let attempts: [[String]]
        switch engine {
        case .demucs:
            var base = ["-n", item.model.id]
            if item.twoStems { base += ["--two-stems", "vocals"] }
            let tail = ["-o", out.path, item.url.path]
            attempts = ["mps", "cpu"].map { base + ["-d", $0] + tail }
        case .audioSeparator:
            attempts = [[item.url.path, "-m", item.model.id, "--model_file_dir", item.model.directory.path,
                         "--output_dir", out.path, "--output_format", "WAV"]]
        }

        var code: Int32 = -1
        var errorText = ""
        for args in attempts {
            (code, errorText) = await execute(item, tool: tool, args: args)
            if item.cancelled { return }
            if code == 0 { break }
        }

        guard code == 0 else {
            item.status = .failed("\(engine.toolName) exited with error \(code).\n" + errorText)
            return
        }
        let stems = Self.collectStems(engine: engine, model: item.model, title: item.title, in: out)
        guard !stems.isEmpty else {
            item.status = .failed("Output files not found after separation.")
            return
        }
        item.stems = stems
        item.progress = 1
        item.status = .done
    }

    /// Runs the tool once, tracking Demucs progress. Returns the exit code and the end of stderr.
    private func execute(_ item: QueueItem, tool: String, args: [String]) async -> (Int32, String) {
        let engine = item.model.engine
        item.progress = 0
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        let toolDir = (tool as NSString).deletingLastPathComponent
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + toolDir
        p.environment = env
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        item.process = p

        let tail = LogTail()
        err.fileHandleForReading.readabilityHandler = { [weak item] h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            tail.append(s)
            if engine == .demucs, let pct = Self.lastPercent(in: s) {
                Task { @MainActor in item?.progress = Double(pct) / 100 }
            }
        }

        let code: Int32 = await withCheckedContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch {
                tail.append("Failed to launch \(engine.toolName): \(error.localizedDescription)")
                cont.resume(returning: -1)
            }
        }
        err.fileHandleForReading.readabilityHandler = nil
        item.process = nil
        return (code, tail.last(400))
    }

    /// Demucs writes <out>/<model>/<track>/<stem>.wav.
    /// audio-separator writes <out>/<track>_(<Stem>)_<model>.wav, with the stem name in parentheses.
    private static func collectStems(engine: Engine, model: ModelConfig, title: String, in out: URL) -> [StemOutput] {
        let fm = FileManager.default
        let audio = ["wav", "mp3", "flac"]
        switch engine {
        case .demucs:
            let folder = out.appendingPathComponent(model.id).appendingPathComponent(title)
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { audio.contains($0.pathExtension.lowercased()) }
            let order = ["vocals", "drums", "bass", "guitar", "piano", "other", "no_vocals"]
            return files
                .map { StemOutput(stem: $0.deletingPathExtension().lastPathComponent, url: $0) }
                .sorted { (order.firstIndex(of: $0.stem) ?? 99) < (order.firstIndex(of: $1.stem) ?? 99) }
        case .audioSeparator:
            let files = ((try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)) ?? [])
                .filter { audio.contains($0.pathExtension.lowercased()) }
            let stems: [StemOutput] = files.compactMap { f in
                let name = f.deletingPathExtension().lastPathComponent
                guard let open = name.range(of: "_("), let close = name.range(of: ")_", range: open.upperBound..<name.endIndex)
                else { return nil }
                return StemOutput(stem: String(name[open.upperBound..<close.lowerBound]), url: f)
            }
            // Keep the extracted instrument first, the remainder second.
            return stems.sorted { !$0.stem.hasPrefix("No ") && $1.stem.hasPrefix("No ") }
        }
    }

    /// Demucs prints tqdm bars like " 45%|████ | 9.9/21.8"; take the last percentage in a chunk.
    nonisolated static func lastPercent(in s: String) -> Int? {
        var result: Int?
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "%", i + 1 < chars.count, chars[i + 1] == "|" {
                var j = i - 1
                var digits = ""
                while j >= 0, chars[j].isNumber { digits = String(chars[j]) + digits; j -= 1 }
                if let n = Int(digits), n <= 100 { result = n }
            }
            i += 1
        }
        return result
    }
}

/// Thread-safe capture of the end of Demucs' stderr for error messages.
final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        text += s
        if text.count > 8000 { text = String(text.suffix(4000)) }
    }
    func last(_ n: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        let cleaned = text.replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.split(separator: "\n").filter { !$0.contains("%|") }
        return String(lines.joined(separator: "\n").suffix(n))
    }
}

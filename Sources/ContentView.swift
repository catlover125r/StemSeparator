import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct StemSeparatorApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var queue = QueueManager()

    var body: some Scene {
        WindowGroup("Stem Separator") {
            RootView()
                .environmentObject(store)
                .environmentObject(queue)
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ModelStore

    var body: some View {
        Group {
            if store.setupComplete {
                ContentView()
            } else {
                SetupView(onDone: { store.setupComplete = true })
            }
        }
    }
}

extension ModelConfig {
    /// The stems this model produces, for the summary line under the model name.
    func stemNames(twoStems: Bool) -> [String] {
        switch engine {
        case .audioSeparator: return ["Woodwinds", "No Woodwinds"]
        case .demucs:
            if twoStems { return ["Vocals", "Instrumental"] }
            return id == "htdemucs_6s"
                ? ["Vocals", "Drums", "Bass", "Guitar", "Piano", "Other"]
                : ["Vocals", "Drums", "Bass", "Other"]
        }
    }
    /// Short technical name shown in the header, e.g. "htdemucs · Apple GPU".
    var technicalName: String {
        let name = id.hasSuffix(".pth") ? String(id.dropLast(4)) : id
        let device: String = engine == .demucs ? "Apple GPU" : "CPU"
        return name + " · " + device
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var queue: QueueManager
    @AppStorage("sep.modelID") private var modelID = "htdemucs"
    @AppStorage("sep.twoStems") private var twoStems = true
    @State private var showModels = false

    private var installedModels: [ModelConfig] { ModelConfig.all.filter { store.installed.contains($0.id) } }
    private var model: ModelConfig {
        installedModels.first { $0.id == modelID } ?? installedModels.first ?? ModelConfig.all[0]
    }
    private var tracksLabel: String {
        if model.engine != .demucs || twoStems { return "2 Tracks" }
        return fullTracksTitle
    }
    private var fullTracksTitle: String { model.id == "htdemucs_6s" ? "6 Tracks" : "4 Tracks" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            if queue.items.isEmpty {
                DropZoneView(compact: false, tracksLabel: tracksLabel, onAdd: add).padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        DropZoneView(compact: true, tracksLabel: tracksLabel, onAdd: add)
                        ForEach(queue.items) { item in QueueItemRow(item: item) }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .onOpenURL { add([$0]) }
        .sheet(isPresented: $showModels) {
            SetupView(isSheet: true, onDone: { showModels = false })
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("Stem Separator").font(.system(size: 22, weight: .semibold))
            Spacer()
            Button { showModels = true } label: { Label("Models", systemImage: "arrow.down.circle") }
                .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(Color.primary.opacity(0.03))
    }

    private var controls: some View {
        HStack(alignment: .top) {
            if model.engine == .demucs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tracks").font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        segment("2 Tracks", selected: twoStems) { twoStems = true }
                        segment(fullTracksTitle, selected: !twoStems) { twoStems = false }
                    }
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Menu {
                    ForEach(installedModels) { m in
                        Button(m.label) { modelID = m.id }
                    }
                    Divider()
                    Button("Manage Models…") { showModels = true }
                } label: {
                    Text(model.technicalName).font(.system(.callout, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                Text(model.stemNames(twoStems: twoStems).joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func add(_ urls: [URL]) {
        queue.add(urls, model: model, twoStems: twoStems, tool: store.toolPath(for: model.engine))
    }
}

struct DropZoneView: View {
    let compact: Bool
    let tracksLabel: String
    let onAdd: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            Image(systemName: "waveform")
                .font(.system(size: compact ? 20 : 54, weight: .ultraLight))
            if compact {
                Text("Drop more files here").font(.callout)
            } else {
                Text("Drop audio files here").font(.title3.weight(.semibold))
                Text("MP3 · WAV · FLAC · M4A · AIFF").font(.callout)
                Text(tracksLabel).font(.callout)
                Button("Choose Files…") { choose() }
                    .controlSize(.large)
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(targeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity, minHeight: compact ? 70 : 0, maxHeight: compact ? 70 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.45))
                .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 22))
        )
        .contentShape(Rectangle())
        .onTapGesture { if compact { choose() } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(u)
                    }
                }
                await MainActor.run { onAdd(urls) }
            }
            return true
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.allowedContentTypes = [.audio]
        if p.runModal() == .OK { onAdd(p.urls) }
    }
}

struct QueueItemRow: View {
    @ObservedObject var item: QueueItem
    @EnvironmentObject var queue: QueueManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { queue.remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(item.status == .running ? "Cancel" : "Remove")
            }
            switch item.status {
            case .running:
                if item.progress > 0 { ProgressView(value: item.progress) } else { ProgressView().progressViewStyle(.linear) }
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            case .done:
                StemSaveButtons(item: item)
            case .waiting:
                EmptyView()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusText: String {
        switch item.status {
        case .waiting: return "Waiting"
        case .running:
            if item.model.engine == .audioSeparator { return "Separating… this can take a minute or two" }
            return item.progress > 0 ? "Separating… \(Int(item.progress * 100))%" : "Starting…"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

struct StemSaveButtons: View {
    @ObservedObject var item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(item.stems) { s in
                    Button("Save \(s.label)") { save(s) }
                }
            }
            HStack {
                if item.stems.count > 1 { Button("Save All…") { saveAll() } }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(item.stems.map(\.url))
                }
            }
        }
        .controlSize(.small)
    }

    private func save(_ s: StemOutput) {
        let p = NSSavePanel()
        p.nameFieldStringValue = "\(item.title) - \(s.label).\(s.url.pathExtension)"
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let dest = p.url else { return }
        copy(s.url, to: dest)
    }

    private func saveAll() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Save Here"
        guard p.runModal() == .OK, let dir = p.url else { return }
        for s in item.stems {
            copy(s.url, to: dir.appendingPathComponent("\(item.title) - \(s.label).\(s.url.pathExtension)"))
        }
    }

    private func copy(_ src: URL, to dest: URL) {
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

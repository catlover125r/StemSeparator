import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct StemSeparatorApp: App {
    @StateObject private var store = ModelStore()
    @StateObject private var queue = QueueManager()

    var body: some Scene {
        WindowGroup {
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
        .frame(minWidth: 560, minHeight: 520)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ModelStore
    @EnvironmentObject var queue: QueueManager
    @AppStorage("modelID") private var modelID = "htdemucs"
    @AppStorage("twoStems") private var twoStems = true
    @State private var showModels = false

    private var installedModels: [ModelConfig] { ModelConfig.all.filter { store.installed.contains($0.id) } }
    private var model: ModelConfig {
        installedModels.first { $0.id == modelID } ?? installedModels.first ?? ModelConfig.all[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("Model", selection: Binding(get: { model.id }, set: { modelID = $0 })) {
                    ForEach(installedModels) { Text($0.label).tag($0.id) }
                }
                .fixedSize()
                Toggle("Vocals and instrumental only", isOn: $twoStems)
                    .toggleStyle(.checkbox)
                Spacer()
                Button { showModels = true } label: { Label("Models", systemImage: "arrow.down.circle") }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()

            if queue.items.isEmpty {
                DropZoneView(compact: false, onAdd: add).padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        DropZoneView(compact: true, onAdd: add)
                        ForEach(queue.items) { item in QueueItemRow(item: item) }
                    }
                    .padding(20)
                }
            }
        }
        .onOpenURL { add([$0]) }
        .sheet(isPresented: $showModels) {
            SetupView(isSheet: true, onDone: { showModels = false })
        }
    }

    private func add(_ urls: [URL]) {
        queue.add(urls, model: model, twoStems: twoStems, demucs: store.demucsPath)
    }
}

struct DropZoneView: View {
    let compact: Bool
    let onAdd: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: compact ? 18 : 40, weight: .light))
            Text(compact ? "Drop more files here" : "Drop audio files here")
                .font(compact ? .callout : .title3)
            if !compact {
                Text("or click to choose").font(.callout).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(targeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity, minHeight: compact ? 64 : 0, maxHeight: compact ? 64 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
        )
        .contentShape(Rectangle())
        .onTapGesture { choose() }
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
                ProgressView(value: item.progress)
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
        case .running: return item.progress > 0 ? "Separating… \(Int(item.progress * 100))%" : "Starting…"
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

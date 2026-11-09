import SwiftUI
import AppKit

/// First-run screen (and the "Models" sheet): checks for the separation tools and downloads models.
struct SetupView: View {
    @EnvironmentObject var store: ModelStore
    var isSheet = false
    var onDone: () -> Void

    @State private var selected: Set<String> = ["htdemucs"]

    private var toDownload: [ModelConfig] {
        ModelConfig.all.filter { selected.contains($0.id) && !store.installed.contains($0.id) }
    }
    private var downloadBytes: Int64 { toDownload.reduce(0) { $0 + $1.totalBytes } }
    private var canFinish: Bool { isSheet || ModelConfig.all.contains(where: store.usable) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tint)
                Text(isSheet ? "Models" : "Welcome to StemSeparator")
                    .font(.title.weight(.semibold))
                Text("Songs are split by AI models. Pick the ones to download. They are stored once on this Mac and work offline afterwards.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                toolRow(.demucs, note: "Runs the Standard, High quality and Six stems models.")
                toolRow(.audioSeparator, note: "Optional. Runs the Woodwinds model (about 1 GB to install).")
            }

            VStack(spacing: 8) {
                ForEach(ModelConfig.all) { m in modelRow(m) }
            }

            Text("Demucs models are saved to ~/.cache/torch/hub/checkpoints. Woodwinds is saved to ~/Library/Application Support/StemSeparator.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 700)
        .onAppear { store.refresh() }
    }

    // MARK: Tools

    private func toolRow(_ engine: Engine, note: String) -> some View {
        let path = store.toolPath(for: engine)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: path != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(path != nil ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                if let path {
                    Text("\(engine.toolName) is installed").fontWeight(.medium)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("\(engine.toolName) isn't installed yet").fontWeight(.medium)
                    Text(note).font(.caption).foregroundStyle(.secondary)
                    Text("Run this in Terminal, then click Check Again:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(engine.installCommand)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(engine.installCommand, forType: .string)
                        }
                        Button("Check Again") { store.refresh() }
                    }
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Models

    private func modelRow(_ m: ModelConfig) -> some View {
        let isInstalled = store.installed.contains(m.id)
        let state = store.downloads[m.id]
        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isInstalled || selected.contains(m.id) },
                set: { on in if on { selected.insert(m.id) } else { selected.remove(m.id) } }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(isInstalled || store.isDownloading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(m.label, systemImage: m.icon).fontWeight(.medium)
                    Spacer()
                    if isInstalled {
                        Label("Downloaded", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                    } else {
                        Text(formatBytes(m.totalBytes)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(m.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let state, state.active {
                    HStack {
                        ProgressView(value: state.fraction)
                        Text("\(Int(state.fraction * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } else if let err = state?.error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if store.isDownloading {
                Button("Cancel Download") { store.cancelDownload() }
            } else {
                Button(toDownload.isEmpty ? "Download" : "Download (\(formatBytes(downloadBytes)))") {
                    store.startDownload(toDownload)
                }
                .disabled(toDownload.isEmpty)
                .keyboardShortcut(canFinish ? nil : .defaultAction)
            }
            Spacer()
            Button(isSheet ? "Done" : "Continue") { onDone() }
                .disabled(!canFinish || store.isDownloading)
                .keyboardShortcut(canFinish ? .defaultAction : nil)
        }
        .controlSize(.large)
    }
}

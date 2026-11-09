import SwiftUI
import AppKit

/// First-run screen (and the "Models" sheet): checks for Demucs and downloads separation models.
struct SetupView: View {
    @EnvironmentObject var store: ModelStore
    var isSheet = false
    var onDone: () -> Void

    @State private var selected: Set<String> = ["htdemucs"]

    private var toDownload: [ModelConfig] {
        ModelConfig.all.filter { selected.contains($0.id) && !store.installed.contains($0.id) }
    }
    private var downloadBytes: Int64 { toDownload.reduce(0) { $0 + $1.totalBytes } }
    private var canFinish: Bool { isSheet || (store.demucsPath != nil && !store.installed.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tint)
                Text(isSheet ? "Models" : "Welcome to StemSeparator")
                    .font(.title.weight(.semibold))
                Text("Songs are split by Demucs, an AI model. Pick the models to download. They are stored once on this Mac and work offline afterwards.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            demucsRow

            VStack(spacing: 8) {
                ForEach(ModelConfig.all) { m in modelRow(m) }
            }

            Text("Saved to ~/.cache/torch/hub/checkpoints, the same place Demucs keeps them.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(minWidth: 540, minHeight: isSheet ? 560 : 0)
        .onAppear { store.refresh() }
    }

    // MARK: Demucs

    private var demucsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: store.demucsPath != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.demucsPath != nil ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                if let path = store.demucsPath {
                    Text("Demucs is installed").fontWeight(.medium)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("Demucs isn't installed yet").fontWeight(.medium)
                    Text("Run this in Terminal, then click Check Again:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("pip3 install demucs")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("pip3 install demucs", forType: .string)
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

import AppKit
import SwiftUI

/// Übersicht & Download aller Modelle – einmal herunterladen, danach komplett offline.
struct ModelsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Text("Alle Modelle laufen ausschließlich lokal auf deinem Mac. Lade die gewünschten Modelle einmal herunter – danach funktioniert die App ohne Internetverbindung.")
                    .font(.callout)
                LabeledContent("Arbeitsspeicher", value: String(format: "%.0f GB", SystemInfo.physicalMemoryGB))
                LabeledContent("Speicherort") {
                    Button(AppPaths.root.path) { NSWorkspace.shared.open(AppPaths.root) }
                        .buttonStyle(.link)
                }
            }

            Section("Übersetzung – TranslateGemma (Google, Jan. 2026, MLX/GPU)") {
                ForEach(GemmaModel.all) { model in
                    modelRow(
                        key: model.repo,
                        title: model.title,
                        subtitle: "\(model.repo) · \(model.approxSize) · ab ~\(Int(model.minRAMGB)) GB RAM"
                            + (model.repo == GemmaModel.recommended.repo ? " · empfohlen für diesen Mac" : ""),
                        downloaded: state.translator.isDownloaded(model.repo),
                        download: { state.download(gemma: model.repo) },
                        delete: { state.delete(gemma: model.repo) })
                }
                Text("Apple Übersetzen benötigt keinen Download hier: Sprachen unter Systemeinstellungen → Allgemein → Sprache & Region → Übersetzungssprachen laden.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Transkription – CoreML (GPU / Neural Engine)") {
                ForEach(ASREngine.allCases) { engine in
                    modelRow(
                        key: engine.rawValue,
                        title: engine.title,
                        subtitle: engine.detail,
                        downloaded: state.transcriber.isDownloaded(engine),
                        download: { state.download(asr: engine) },
                        delete: { state.delete(asr: engine) })
                }
            }
        }
        .formStyle(.grouped)
        .id(state.refreshToken)
    }

    @ViewBuilder
    private func modelRow(key: String, title: String, subtitle: String, downloaded: Bool,
                          download: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                if let progress = state.downloads[key] {
                    ProgressView(value: progress)
                    Text(state.downloadStatus[key] ?? "")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.downloads[key] != nil {
                ProgressView().controlSize(.small)
            } else if downloaded {
                Label("Offline bereit", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Modell löschen")
            } else {
                Button("Herunterladen", action: download)
            }
        }
        .padding(.vertical, 2)
    }
}

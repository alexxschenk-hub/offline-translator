import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

struct TranslateView: View {
    @EnvironmentObject var state: AppState
    @State private var appleConfig: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 12) {
                editorColumn(
                    title: "\(state.direction.source.flag) \(state.direction.source.displayName)",
                    text: $state.sourceText,
                    editable: true)

                Button {
                    state.swapDirection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .help("Richtung tauschen (⌘⇧S)")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.isTranslating)

                editorColumn(
                    title: "\(state.direction.target.flag) \(state.direction.target.displayName)",
                    text: $state.translatedText,
                    editable: false)
            }

            footer
        }
        .translationTask(appleConfig) { session in
            await runAppleTranslation(session)
        }
    }

    // MARK: - Teile

    private var header: some View {
        HStack {
            Picker("Engine", selection: $state.translationEngine) {
                ForEach(TranslationEngine.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 360)

            if state.translationEngine == .translateGemma {
                Picker("Modell", selection: $state.gemmaRepo) {
                    ForEach(GemmaModel.all) { model in
                        Text(model.title).tag(model.repo)
                    }
                }
                .frame(maxWidth: 380)
                .disabled(state.isTranslating)
            }
            Spacer()
        }
    }

    private func editorColumn(title: String, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if editable {
                    Button("Datei öffnen …", systemImage: "doc") { openTextFile() }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Textdatei laden")
                    Button("Leeren", systemImage: "xmark.circle") {
                        state.sourceText = ""; state.translatedText = ""
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("Leeren")
                } else {
                    Button("Kopieren", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.translatedText, forType: .string)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("In die Zwischenablage kopieren")
                    .disabled(state.translatedText.isEmpty)
                    Button("Speichern …", systemImage: "square.and.arrow.down") { saveTranslation() }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Übersetzung als Textdatei speichern")
                        .disabled(state.translatedText.isEmpty)
                }
            }
            TextEditor(text: text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .disabled(!editable && state.isTranslating)
            Text("\(text.wrappedValue.count) Zeichen")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if state.isTranslating {
                ProgressView().controlSize(.small)
            }
            Text(state.translationStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            InfoBadge(text: "100 % lokal – keine Daten verlassen den Mac")
            if state.isTranslating {
                Button("Stopp", role: .cancel) { state.cancelTranslation() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Button {
                startTranslation()
            } label: {
                Label("Übersetzen", systemImage: "arrow.right.circle.fill")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(state.isTranslating || state.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Aktionen

    private func startTranslation() {
        state.translate(appleHandler: {
            state.isTranslating = true
            state.translatedText = ""
            state.translationStatus = "Übersetze mit Apple Übersetzen …"
            let source = state.direction.source.localeLanguage
            let target = state.direction.target.localeLanguage
            if var config = appleConfig, config.source == source, config.target == target {
                config.invalidate()
                appleConfig = config
            } else {
                appleConfig = TranslationSession.Configuration(source: source, target: target)
            }
        })
    }

    private func runAppleTranslation(_ session: TranslationSession) async {
        let text = await MainActor.run { state.sourceText }
        let started = Date()
        do {
            // Absatzweise übersetzen, damit Formatierung erhalten bleibt
            let lines = text.components(separatedBy: "\n")
            let requests = lines.enumerated().compactMap { (index, line) -> TranslationSession.Request? in
                line.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : TranslationSession.Request(sourceText: line, clientIdentifier: String(index))
            }
            var translated = lines
            let responses = try await session.translations(from: requests)
            for response in responses {
                if let id = response.clientIdentifier, let index = Int(id) {
                    translated[index] = response.targetText
                }
            }
            let result = translated.joined(separator: "\n")
            await MainActor.run {
                state.translatedText = result
                state.translationStatus = String(format: "Fertig in %.1f s (Apple)", Date().timeIntervalSince(started))
                state.isTranslating = false
            }
        } catch {
            await MainActor.run {
                state.translationStatus = ""
                state.errorMessage = "Apple Übersetzen: \(error.localizedDescription)\n\nTipp: Unter Systemeinstellungen → Allgemein → Sprache & Region → Übersetzungssprachen Deutsch und Englisch für die Offline-Nutzung laden."
                state.isTranslating = false
            }
        }
    }

    private func openTextFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "srt") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            state.sourceText = text
            state.translatedText = ""
        }
    }

    private func saveTranslation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Übersetzung_\(state.direction.target.rawValue).txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try state.translatedText.write(to: url, atomically: true, encoding: .utf8) }
            catch { state.errorMessage = error.localizedDescription }
        }
    }
}

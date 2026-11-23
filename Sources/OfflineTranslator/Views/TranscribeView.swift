import SwiftUI
import UniformTypeIdentifiers

struct TranscribeView: View {
    @EnvironmentObject var state: AppState
    var onSendToTranslator: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                Section("Dateien") {
                    LabeledContent("Audiodatei") {
                        HStack {
                            TextField("/Pfad/zur/Datei.mp3 oder .m4a", text: $state.inputPath)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { state.setInput(URL(fileURLWithPath: state.inputPath)) }
                            Button("Wählen …") { state.chooseInput() }
                        }
                    }
                    LabeledContent("Ausgabedatei") {
                        HStack {
                            TextField("/Pfad/zur/Ausgabe.txt", text: $state.outputPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Wählen …") { state.chooseOutput() }
                        }
                    }
                    Picker("Ausgabeformat", selection: $state.outputFormat) {
                        ForEach(OutputFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: state.outputFormat) { state.outputFormatChanged() }
                }

                Section("Erkennung") {
                    Picker("Modell", selection: $state.asrEngine) {
                        ForEach(ASREngine.allCases) { Text($0.title).tag($0) }
                    }
                    Text(state.asrEngine.detail)
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Gesprochene Sprache", selection: $state.spokenLanguage) {
                        ForEach(SpokenLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Recheneinheit", selection: $state.computeChoice) {
                        ForEach(ComputeChoice.allCases) { Text($0.title).tag($0) }
                    }
                    if !state.transcriber.isDownloaded(state.asrEngine) {
                        Label("Das Modell wird beim ersten Start einmalig heruntergeladen (Internet nötig). Danach läuft alles offline.",
                              systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(state.isTranscribing)
            .id(state.refreshToken)

            VStack(alignment: .leading, spacing: 6) {
                if state.isTranscribing || state.transcriptionProgress > 0 {
                    ProgressView(value: state.transcriptionProgress)
                }
                HStack {
                    Text(state.transcriptionStatus)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if !state.transcriptPreview.isEmpty, !state.isTranscribing {
                        Button("Im Finder zeigen") { state.revealOutput() }
                        Button("Übersetzen …") { onSendToTranslator() }
                    }
                    if state.isTranscribing {
                        Button("Abbrechen", role: .cancel) { state.cancelTranscription() }
                    } else {
                        Button {
                            state.startTranscription()
                        } label: {
                            Label("Transkribieren", systemImage: "waveform.badge.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(state.inputPath.isEmpty)
                    }
                }
            }
            .padding(.horizontal)

            if !state.transcriptPreview.isEmpty {
                ScrollView {
                    Text(state.transcriptPreview)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 120)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .padding(.horizontal)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .overlay(Text("Audiodatei hier ablegen").font(.title2).padding()
                        .background(.regularMaterial, in: Capsule()))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.setInput(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }
}

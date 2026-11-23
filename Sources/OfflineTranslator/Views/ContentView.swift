import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: Tab = .translate

    enum Tab: Hashable { case translate, transcribe, models }

    var body: some View {
        TabView(selection: $tab) {
            TranslateView()
                .tabItem { Label("Übersetzen", systemImage: "character.bubble") }
                .tag(Tab.translate)
            TranscribeView(onSendToTranslator: {
                state.sendTranscriptToTranslator()
                tab = .translate
            })
                .tabItem { Label("Transkribieren", systemImage: "waveform") }
                .tag(Tab.transcribe)
            ModelsView()
                .tabItem { Label("Modelle", systemImage: "cpu") }
                .tag(Tab.models)
        }
        .padding()
        .alert("Fehler", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

/// Kleiner Hinweis-Baustein
struct InfoBadge: View {
    let text: String
    var systemImage: String = "lock.shield"
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

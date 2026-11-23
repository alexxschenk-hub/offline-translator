# Offline Übersetzer & Transkription (macOS)

Native SwiftUI-App für **Apple-Silicon-Macs**. Läuft nach dem einmaligen Modell-Download **komplett offline**:

- **Übersetzen** Englisch ⇄ Deutsch: Text eintippen oder einfügen, `.txt`/`.md` öffnen, Ergebnis kopieren oder speichern
- **Transkribieren** von Audiodateien (mp3, m4a, wav, aiff …) auf Deutsch oder Englisch: Pfad eingeben, auswählen oder per Drag & Drop ablegen, Ausgabepfad und Format (TXT, SRT, VTT, Markdown mit Zeitmarken) wählen
- Das Transkript lässt sich mit einem Klick an den Übersetzer übergeben
- Rechenarbeit auf **GPU (Metal)** oder **Neural Engine**, ohne Cloud und ohne Konto

## Verwendete Modelle (Stand November 2026)

### Übersetzung: Google **TranslateGemma** (Januar 2026)
Auf Übersetzung spezialisierte Variante von Gemma 3 (55 Sprachen). Laut Googles technischem Bericht schlägt das 12B-Modell auf WMT24++ (MetricX) das deutlich größere Gemma 3 27B. Es läuft über **MLX** direkt auf der GPU.

| Modell | Größe | Empfohlen ab |
|---|---|---|
| TranslateGemma 27B 4-bit | ≈ 16 GB | 32–48 GB RAM (höchste Qualität) |
| TranslateGemma 12B 8-bit | ≈ 12,5 GB | 24 GB RAM |
| **TranslateGemma 12B 4-bit** (Standard) | ≈ 6,7 GB | 16 GB RAM |
| TranslateGemma 4B 4-bit | ≈ 2,5 GB | 8 GB RAM |

Die App wählt passend zum Arbeitsspeicher automatisch ein Modell vor.
Alternativ lässt sich **Apple Übersetzen** (systemeigen, offline nach Download der Sprachpakete) nutzen.

### Transkription
| Modell | Bibliothek | Hinweis |
|---|---|---|
| **Whisper large-v3** (Standard) | WhisperKit (CoreML) | höchste Robustheit, Zeichensetzung, Zeitstempel, ≈ 3 GB |
| Whisper large-v3 Turbo | WhisperKit | ca. 5× schneller bei fast gleicher Qualität |
| **Parakeet TDT Ultra** | FluidAudio (CoreML) | Nachtraining von NVIDIA Parakeet v3, genauer als v3 auf allen Benchmarks, extrem schnell |
| Parakeet TDT v3 | FluidAudio | 25 europäische Sprachen, extrem schnell |

Bei Deutsch liegen Whisper large-v3 und Parakeet je nach Test etwa gleichauf. Parakeet ist aber um ein Vielfaches schneller. Tipp: Teste beide an deinen eigenen Aufnahmen.

## Voraussetzungen
- Mac mit Apple Silicon (M1 oder neuer)
- macOS 15 Sequoia oder neuer
- **Xcode 26 oder neuer** (Swift 6.2). Die Command Line Tools allein reichen nicht, weil MLX seine Metal-Shader mit Xcode kompiliert.
- Internet nur für den einmaligen Modell-Download (Reiter „Modelle“)

## Bauen & Starten

### Variante A: in Xcode (am einfachsten)
1. `OfflineTranslator/Package.swift` in Xcode öffnen (Doppelklick oder `open Package.swift`)
2. Warten, bis die Pakete geladen sind. Falls Xcode fragt, ob es Makros/Plugins vertrauen soll: „Trust & Enable“
3. Oben als Ziel **OfflineTranslator → My Mac** wählen und **⌘R** drücken
   Für die volle Geschwindigkeit: *Product → Scheme → Edit Scheme → Run → Build Configuration: Release*

### Variante B: fertige `.app` erzeugen
```bash
cd OfflineTranslator
./scripts/build-app.sh
open "dist/Offline Übersetzer.app"
```
Die App kann anschließend nach `/Programme` gezogen werden.

## Erste Schritte
1. Im Reiter **Modelle** die gewünschten Modelle herunterladen (z. B. TranslateGemma 12B und Whisper large-v3)
2. Ab jetzt ist kein Internet mehr nötig, die WLAN-Verbindung kann getrennt werden
3. **Übersetzen**: Text links eingeben, Richtung mit ⇄ tauschen, **⌘↩** übersetzt
4. **Transkribieren**: Audiodatei wählen oder ablegen, Ausgabedatei und Format wählen, Sprache (oder „Automatisch“) und Modell wählen, dann **Transkribieren**

Hinweis: Beim **ersten** Laden eines Whisper-Modells kompiliert CoreML es für deinen Chip. Das dauert einige Minuten (bei large-v3 auf der Neural Engine teils länger). Danach startet es schnell.

## Speicherort der Modelle
`~/Library/Application Support/OfflineTranslator/` (lässt sich im Reiter „Modelle“ direkt öffnen; Modelle können dort auch gelöscht werden)

## Aufbau
```
OfflineTranslator/
├── Package.swift                     SwiftPM-Projekt (WhisperKit, FluidAudio, mlx-swift-lm, swift-transformers)
├── Resources/Info.plist              für das .app-Bundle
├── scripts/build-app.sh              Release-Build + App-Bundle
└── Sources/OfflineTranslator/
    ├── App/            App-Einstieg, zentraler Zustand
    ├── Services/       TranslateGemma (MLX), Transkription (WhisperKit/FluidAudio), Modellkatalog
    ├── Support/        HF-Downloader, Transkript-Export (TXT/SRT/VTT/MD), Pfade, Sprachen
    └── Views/          Übersetzen, Transkribieren, Modelle
```

## Fehlerbehebung
- **„Failed to load the default metallib“**: mit Xcode bzw. `scripts/build-app.sh` bauen, nicht mit `swift build`
- **Apple Übersetzen meldet Fehler**: Systemeinstellungen → Allgemein → Sprache & Region → Übersetzungssprachen, dort Deutsch und Englisch laden
- **Wenig RAM / langsam**: ein kleineres TranslateGemma-Modell wählen oder bei der Transkription Parakeet bzw. Whisper Turbo nutzen

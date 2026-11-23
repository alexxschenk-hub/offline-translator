#!/usr/bin/env bash
# Baut "Offline Übersetzer.app" (Release, Apple Silicon) in ./dist
# Voraussetzung: Xcode 26 oder neuer (xcode-select -p muss auf Xcode zeigen, nicht nur auf die CLT).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DERIVED="$ROOT/.build/xcode"
APP_NAME="Offline Übersetzer"
APP="$ROOT/dist/$APP_NAME.app"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "⚠️  Diese App benötigt einen Mac mit Apple Silicon (M1 oder neuer)." >&2
  exit 1
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *".app/Contents/Developer"* ]]; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
  echo "❌ Aktives Entwicklerverzeichnis ist '$DEV_DIR' (nur Command Line Tools)." >&2
  if [[ -n "$XCODE_APP" ]]; then
    echo "   Xcode gefunden: $XCODE_APP – bitte aktivieren mit:" >&2
    echo "     sudo xcode-select -s \"$XCODE_APP/Contents/Developer\"" >&2
    echo "     sudo xcodebuild -license accept" >&2
    echo "     xcodebuild -downloadComponent MetalToolchain" >&2
  else
    echo "   Bitte zuerst Xcode (26 oder neuer) aus dem App Store installieren." >&2
  fi
  exit 1
fi

echo "▶︎ Baue mit xcodebuild (MLX benötigt xcodebuild für die Metal-Shader) …"
xcodebuild \
  -scheme OfflineTranslator \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  ONLY_ACTIVE_ARCH=YES \
  build | (command -v xcpretty >/dev/null && xcpretty || cat)

PRODUCTS="$DERIVED/Build/Products/Release"

echo "▶︎ Erstelle App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/OfflineTranslator" "$APP/Contents/MacOS/OfflineTranslator"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM-Ressourcen-Bundles (u. a. mlx-swift_Cmlx.bundle mit default.metallib)
shopt -s nullglob
for bundle in "$PRODUCTS"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
# Metallib zusätzlich neben die Binary legen (MLX sucht dort zuerst)
for lib in "$PRODUCTS"/*.metallib; do
  cp "$lib" "$APP/Contents/MacOS/"
done
# Dynamische Frameworks, falls vorhanden
for fw in "$PRODUCTS"/PackageFrameworks/*.framework "$PRODUCTS"/*.framework; do
  cp -R "$fw" "$APP/Contents/Frameworks/"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/OfflineTranslator" 2>/dev/null || true

echo "▶︎ Signiere ad-hoc …"
codesign --force --deep --sign - "$APP"

echo "✅ Fertig: $APP"
echo "   Starten mit: open \"$APP\""

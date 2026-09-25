#!/bin/zsh
# Baut Depflush.app
#   ./build.sh              bauen (build/Depflush.app, dist/Depflush.zip)
#   ./build.sh --install    bauen, nach ~/Applications kopieren und starten
#   ./build.sh --release    bauen, signieren und bei Apple notarisieren (braucht Apple-Developer-Konto)
# Optionen lassen sich kombinieren: ./build.sh --release --install
#
# Signatur:
#   - Ohne Developer-ID-Zertifikat wird ad-hoc signiert (wie bisher). macOS zeigt beim ersten Start
#     eine Warnung; Nutzer müssen unter Systemeinstellungen → Datenschutz & Sicherheit „Trotzdem öffnen“.
#   - Mit Zertifikat (und .signing.env) wird mit Developer ID signiert; mit --release zusätzlich
#     notarisiert und das Ticket angeheftet. Dann startet die App ohne Warnung.
#   Einrichtung: siehe README → „Signing and notarization“.
set -e
cd "$(dirname "$0")"
APP="build/Depflush.app"
INSTALL=0; RELEASE=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    --release) RELEASE=1 ;;
    *) echo "Unbekannte Option: $a" >&2; exit 2 ;;
  esac
done

[ -f .signing.env ] && source ./.signing.env
if [ -z "$DEVELOPER_ID" ]; then
  DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
fi

if [ ! -f Resources/AppIcon.icns ]; then
  echo "→ Icon erzeugen"
  swift make_icon.swift Resources/icon_1024.png
  ICONSET=Resources/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o Resources/AppIcon.icns
  rm -rf $ICONSET
fi

echo "→ Kompilieren"
rm -rf build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal Binary: Apple Silicon + Intel
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $ARCH-apple-macosx14.0 -parse-as-library \
    Sources/*.swift -o "build/Depflush-$ARCH"
done
lipo -create build/Depflush-arm64 build/Depflush-x86_64 -output "$APP/Contents/MacOS/Depflush"
rm build/Depflush-arm64 build/Depflush-x86_64
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Hardened Runtime immer aktiv – so verhält sich jeder Build wie die spätere notarisierte Version
if [ -n "$DEVELOPER_ID" ]; then
  echo "→ Signieren: $DEVELOPER_ID"
  codesign --force --options runtime --timestamp --entitlements Depflush.entitlements -s "$DEVELOPER_ID" "$APP"
else
  echo "→ Ad-hoc signieren (kein Developer-ID-Zertifikat gefunden)"
  codesign --force --options runtime --entitlements Depflush.entitlements -s - "$APP"
fi
codesign --verify --strict "$APP"

zip_app() {
  mkdir -p dist
  rm -f dist/Depflush.zip
  ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Depflush.zip
}
zip_app

if [ $RELEASE = 1 ]; then
  if [ -z "$DEVELOPER_ID" ] || [ -z "$NOTARY_PROFILE" ]; then
    echo "✗ --release braucht ein Developer-ID-Zertifikat und NOTARY_PROFILE in .signing.env" >&2
    echo "  (siehe README → „Signing and notarization“)" >&2
    exit 1
  fi
  echo "→ Bei Apple notarisieren (dauert meist 1–5 Minuten)"
  xcrun notarytool submit dist/Depflush.zip --keychain-profile "$NOTARY_PROFILE" --wait
  echo "→ Ticket anheften"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  zip_app
fi

if [ $INSTALL = 1 ]; then
  echo "→ Installieren nach ~/Applications"
  osascript -e 'tell application id "de.webloupe.depflush" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "de.webloupe.aufraeumer" to quit' >/dev/null 2>&1 || true
  sleep 1
  mkdir -p ~/Applications
  rm -rf ~/Applications/Depflush.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Depflush.app
fi
echo "✓ Fertig (dist/Depflush.zip)"

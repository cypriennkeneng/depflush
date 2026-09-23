#!/bin/zsh
# Baut Aufräumer.app und installiert sie nach ~/Applications
set -e
cd "$(dirname "$0")"
APP="build/Aufräumer.app"

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
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library \
  Sources/*.swift -o "$APP/Contents/MacOS/Aufraeumer"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep -s - "$APP"

if [ "$1" = "--install" ]; then
  echo "→ Installieren nach ~/Applications"
  osascript -e 'tell application id "de.webloupe.aufraeumer" to quit' >/dev/null 2>&1 || true
  sleep 1
  mkdir -p ~/Applications
  rm -rf ~/Applications/Aufräumer.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Aufräumer.app
fi
echo "✓ Fertig"

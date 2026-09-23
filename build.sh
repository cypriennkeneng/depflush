#!/bin/zsh
# Baut Depflush.app und installiert sie nach ~/Applications
set -e
cd "$(dirname "$0")"
APP="build/Depflush.app"

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
codesign --force --deep -s - "$APP"

if [ "$1" = "--install" ]; then
  echo "→ Installieren nach ~/Applications"
  osascript -e 'tell application id "de.webloupe.depflush" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "de.webloupe.aufraeumer" to quit' >/dev/null 2>&1 || true
  sleep 1
  mkdir -p ~/Applications
  rm -rf ~/Applications/Depflush.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Depflush.app
fi
echo "✓ Fertig"

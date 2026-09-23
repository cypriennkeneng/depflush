# Aufräumer

Native macOS-App (SwiftUI) zum regelmäßigen Aufräumen des Speicherplatzes.

- **Übersicht**: freier Speicher, größte Bereiche, Swap-Hinweis
- **Caches**: App-/Browser-/Entwickler-Caches, alte JetBrains-Versionen, Crash-Dumps, Papierkorb
  (Caches geöffneter Apps werden übersprungen)
- **Entwicklung**: vendor/node_modules ruhender Projekte (nur mit composer.lock / package.json),
  doppelte SQL-Dumps (SHA-256 geprüft), große Dumps zur eigenen Entscheidung
- **Docker**: Build-Cache, ungenutzte Images, gestoppte Container, verwaiste Volumes
- **Menüleiste**: freier Speicher + Mitteilung unter der Warnschwelle
- **Verlauf**: `~/Library/Application Support/Aufraeumer/verlauf.json`

Gelöscht wird nur nach Vorschau + Bestätigung, endgültig (nicht in den Papierkorb).
Geschützte Ordner (Home, Library, Dokumente, Projektordner selbst …) werden nie gelöscht.

## Bauen & installieren
```
./build.sh            # baut build/Aufräumer.app
./build.sh --install  # baut, kopiert nach ~/Applications und startet
```
Benötigt nur die Xcode Command Line Tools (Swift 6), macOS 14+.

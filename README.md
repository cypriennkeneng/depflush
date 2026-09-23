# Depflush

Kostenlose native macOS-App (SwiftUI) zum Aufräumen des Speicherplatzes – mit Fokus auf Entwickler (Docker, vendor/node_modules, SQL-Dumps, IDE-Caches). Website: https://depflush.com · von [Webloupe](https://webloupe.de)

- **Übersicht**: freier Speicher, größte Bereiche, Swap-Hinweis
- **Caches**: App-/Browser-/Entwickler-Caches, alte JetBrains-Versionen, Crash-Dumps, Papierkorb
  (Caches geöffneter Apps werden übersprungen)
- **Entwicklung**: vendor/node_modules ruhender Projekte (nur mit composer.lock / package.json),
  doppelte SQL-Dumps (SHA-256 geprüft), große Dumps zur eigenen Entscheidung
- **Docker**: Build-Cache, ungenutzte Images, gestoppte Container, verwaiste Volumes
- **Menüleiste**: freier Speicher + Mitteilung unter der Warnschwelle
- **Verlauf**: `~/Library/Application Support/Depflush/verlauf.json`

Gelöscht wird nur nach Vorschau + Bestätigung – standardmäßig in den Papierkorb, optional endgültig.
Sprachen: DE / EN / FR (`Sources/Strings.swift`, Prüfung mit `python3 tools/l10n_check.py`).
Geschützte Ordner (Home, Library, Dokumente, Projektordner selbst …) werden nie gelöscht.

## Bauen & installieren
```
./build.sh            # baut build/Depflush.app
./build.sh --install  # baut, kopiert nach ~/Applications und startet
```
Benötigt nur die Xcode Command Line Tools (Swift 6), macOS 14+. Baut ein Universal Binary (Apple Silicon + Intel).

# Changelog

## 1.3.0 – 2026-09-24
- New **Duplicates** section: finds identical photos and videos (optionally all files from 1 MB) in Pictures, Movies, Documents, Desktop and Downloads
- Size → first/last 64 KB → SHA-256; the original stays, and a copy is only removed if the original still exists
- Skips the Photos library, app bundles and app working folders, iCloud-only files, hard links and APFS clones
- Duplicate folders and file types configurable in Settings
- Sidebar no longer disappears after clicking an item

## 1.2.1 – 2026-09-24
- Source code published under GPL-3.0
- "Source code on GitHub" link under Settings → About

## 1.2.0 – 2026-09-24
- New name: **Depflush** (previously "Aufräumer"), bundle ID `de.webloupe.depflush`
- Settings and history carry over from earlier builds
- Links to depflush.com, Web Loupe and the Ko-fi page under Settings → About
- Optional support link in the menu bar after the first cleanup

## 1.1.0 – 2026-09-24
- English, German and French (system language or chosen in Settings)
- Trash mode by default, with "Empty Trash now" after a cleanup; permanent deletion as an option
- Several project folders with automatic detection (~/Sites, ~/Projects, ~/Developer, ~/code …)
- Universal binary: Apple Silicon and Intel
- Welcome screen; more caches: Brave, Edge, Arc, VS Code, Cursor, pnpm, Go, Gradle, CocoaPods, Xcode DerivedData
- Dependencies inside plugins or packages are never preselected

## 1.0.0 – 2026-09-23
- First version: overview, caches, dependencies, duplicate SQL dumps, Docker, menu bar, history, settings

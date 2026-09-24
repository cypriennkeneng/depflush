# Contributing to Depflush

Thanks for helping. Depflush deletes files on other people's Macs, so safety comes before features.

## Ground rules

- Never preselect anything that can't be restored automatically (rebuilt, re-downloaded or restored with one command).
- Items that can lose work (containers, volumes, locally built images, plugin dependencies) must stay unticked and carry a `warning`.
- Don't add network calls, analytics or telemetry.
- Keep the app free of third-party dependencies; it builds with `swiftc` only.

## Build and run

```sh
./build.sh --install
```

Check translations before opening a pull request:

```sh
python3 tools/l10n_check.py
```

## Adding a cache location

Most contributions are a single entry in `CacheScanner.rules` in `Sources/Scanners.swift`:

```swift
CacheRule(title: L("SomeTool – Cache"),
          detail: pkg,                                  // or browser, web, browsers, or your own L("…")
          patterns: ["~/Library/Caches/SomeTool"],      // globs are allowed, "~" is expanded
          bundleIDs: ["com.example.SomeTool"],          // app must be closed before its cache is removed
          appName: "SomeTool"),
```

Then add the translation to `Sources/Strings.swift`:

```swift
"SomeTool – Cache": ["SomeTool – cache", "SomeTool – cache"],   // [English, French]
```

UI texts in the code are written in German and used as translation keys. If German isn't your language, write the key in English and mention it in the pull request; we'll adjust it.

Please tell us in the pull request how the folder comes back after deletion and how big it was on your Mac.

## Pull requests

- One topic per pull request.
- Describe what you tested (macOS version, Apple Silicon or Intel).
- Add a line to `CHANGELOG.md` under "Unreleased".

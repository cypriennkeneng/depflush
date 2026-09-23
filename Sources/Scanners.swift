import Foundation
import AppKit

// MARK: - Übersicht

enum OverviewScanner {
    static func scan(projectRoot: String) async -> [UsageRow] {
        let defs: [(String, String, String?, Pane?)] = [
            ("Docker Desktop", "~/Library/Containers/com.docker.docker", "Images, Container und Volumes", .docker),
            ("Projekte", projectRoot, "vendor/node_modules und SQL-Dumps", .dev),
            ("Thunderbird-Mails", "~/Library/Thunderbird", "Offline-Kopie der Postfächer – in Thunderbird unter Konto → Synchronisation & Speicherplatz begrenzen", nil),
            ("Apple Mail", "~/Library/Mail", nil, nil),
            ("App-Caches", "~/Library/Caches", "Zwischenspeicher der Apps", .caches),
            ("WhatsApp-Medien", "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared", "In WhatsApp: Einstellungen → Speicher → große Dateien löschen", nil),
            ("Claude", "~/Library/Application Support/Claude", "Wird von Claude/Cowork gebraucht", nil),
            ("Chrome-Profil", "~/Library/Application Support/Google", nil, nil),
            ("Adobe", "~/Library/Application Support/Adobe", nil, nil),
            ("Slack", "~/Library/Application Support/Slack", nil, nil),
            ("Discord", "~/Library/Application Support/discord", nil, nil),
            ("Filme", "~/Movies", nil, nil),
            ("Downloads", "~/Downloads", "Selbst durchsehen – enthält persönliche Unterlagen", nil),
            ("Dokumente", "~/Documents", nil, nil),
            ("Schreibtisch", "~/Desktop", nil, nil),
            ("Bilder", "~/Pictures", nil, nil),
            ("iPhone-Backups", "~/Library/Application Support/MobileSync/Backup", "Finder → iPhone → Backups verwalten", nil),
            ("Xcode / Developer", "~/Library/Developer", nil, nil),
            ("npm-, pnpm- & Tool-Caches", "~/.npm", nil, .caches),
        ]
        var rows: [UsageRow] = []
        await withTaskGroup(of: UsageRow?.self) { g in
            for (title, path, hint, pane) in defs {
                g.addTask {
                    let full = Paths.expand(path)
                    guard FileManager.default.fileExists(atPath: full) else { return nil }
                    let size = await Sizer.du([URL(fileURLWithPath: full)])
                    return UsageRow(title: title, path: full, size: size, hint: hint, pane: pane)
                }
            }
            for await r in g { if let r { rows.append(r) } }
        }
        return rows.filter { ($0.size ?? 0) > 200_000_000 }.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    static func swap() async -> Int64? {
        let r = await Shell.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        // "total = 20480.00M  used = 19171.56M  free = ..."
        guard let range = r.out.range(of: #"total = ([0-9.]+)M"#, options: .regularExpression) else { return nil }
        let num = r.out[range].replacingOccurrences(of: "total = ", with: "").replacingOccurrences(of: "M", with: "")
        guard let mb = Double(num) else { return nil }
        return Int64(mb * 1_048_576)
    }
}

// MARK: - Caches

struct CacheRule {
    let title: String
    let detail: String
    let patterns: [String]
    var bundleIDs: [String] = []
    var appName: String? = nil
    var on: Bool = true
}

enum CacheScanner {
    static let rules: [CacheRule] = [
        CacheRule(title: "Google Chrome – Cache", detail: "Browser-Cache, baut sich automatisch neu auf", patterns: ["~/Library/Caches/Google"], bundleIDs: ["com.google.Chrome"], appName: "Google Chrome"),
        CacheRule(title: "Firefox – Cache", detail: "Browser-Cache, baut sich automatisch neu auf", patterns: ["~/Library/Caches/Firefox", "~/Library/Caches/Mozilla"], bundleIDs: ["org.mozilla.firefox"], appName: "Firefox"),
        CacheRule(title: "ChatGPT Atlas – Cache", detail: "Browser-Cache", patterns: ["~/Library/Caches/com.openai.atlas"], bundleIDs: ["com.openai.atlas"], appName: "ChatGPT Atlas"),
        CacheRule(title: "ChatGPT – Cache", detail: "App-Cache", patterns: ["~/Library/Caches/com.openai.chat"], bundleIDs: ["com.openai.chat"], appName: "ChatGPT"),
        CacheRule(title: "Thunderbird – Cache", detail: "Nur der Cache, keine Mails", patterns: ["~/Library/Caches/Thunderbird"], bundleIDs: ["org.mozilla.thunderbird"], appName: "Thunderbird"),
        CacheRule(title: "WhatsApp – Cache", detail: "Nur der Cache, keine Chats", patterns: ["~/Library/Caches/net.whatsapp.WhatsApp"], bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], appName: "WhatsApp"),
        CacheRule(title: "CapCut – Cache", detail: "Vorschau-Cache, deine Projekte bleiben", patterns: ["~/Movies/CapCut/User Data/Cache"], bundleIDs: ["com.lemon.lvoverseas"], appName: "CapCut"),
        CacheRule(title: "Claude – Cache", detail: "Web-Cache der Claude-App (kein Verlauf)", patterns: ["~/Library/Application Support/Claude/Cache", "~/Library/Application Support/Claude/Code Cache"], bundleIDs: ["com.anthropic.claudefordesktop"], appName: "Claude"),
        CacheRule(title: "Slack – Cache", detail: "Web-Cache der Slack-App", patterns: ["~/Library/Application Support/Slack/Cache", "~/Library/Application Support/Slack/Code Cache", "~/Library/Application Support/Slack/Service Worker/CacheStorage"], bundleIDs: ["com.tinyspeck.slackmacgap"], appName: "Slack"),
        CacheRule(title: "Discord – Cache", detail: "Web-Cache der Discord-App", patterns: ["~/Library/Application Support/discord/Cache", "~/Library/Application Support/discord/Code Cache"], bundleIDs: ["com.hnc.Discord"], appName: "Discord"),
        CacheRule(title: "npm – Cache", detail: "Entspricht „npm cache clean --force“", patterns: ["~/.npm/_cacache"]),
        CacheRule(title: "Composer – Cache", detail: "Paket-Downloads, werden bei Bedarf neu geladen", patterns: ["~/Library/Caches/composer", "~/.composer/cache"]),
        CacheRule(title: "Yarn – Cache", detail: "Paket-Downloads", patterns: ["~/Library/Caches/Yarn"]),
        CacheRule(title: "pip – Cache", detail: "Python-Paket-Downloads", patterns: ["~/Library/Caches/pip"]),
        CacheRule(title: "Puppeteer – Browser", detail: "Heruntergeladene Test-Browser, werden bei Bedarf neu geladen", patterns: ["~/.cache/puppeteer"]),
        CacheRule(title: "Playwright – Browser", detail: "Heruntergeladene Test-Browser, werden bei Bedarf neu geladen", patterns: ["~/Library/Caches/ms-playwright"]),
        CacheRule(title: "shopware-cli – Cache", detail: "Tool-Cache", patterns: ["~/Library/Caches/shopware-cli"]),
        CacheRule(title: "Java-/PhpStorm-Crash-Dumps", detail: "Speicherabbilder nach Abstürzen (*.hprof, java_error_*.log)", patterns: ["~/*.hprof", "~/java_error_in_*.log", "~/jbr_err_*.log"]),
        CacheRule(title: "Absturzberichte", detail: "~/Library/Logs/DiagnosticReports", patterns: ["~/Library/Logs/DiagnosticReports/*"]),
    ]

    static func scan() async -> [CleanItem] {
        let running = await MainActor.run { Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }) }
        var items: [CleanItem] = []

        for r in rules {
            let urls = r.patterns.flatMap { Paths.glob($0) }
            guard !urls.isEmpty else { continue }
            let blocked = r.bundleIDs.contains(where: { running.contains($0) }) ? (r.appName ?? "App") : nil
            items.append(CleanItem(id: r.title, title: r.title, detail: r.detail, size: nil,
                                   selected: r.on && blocked == nil, action: .delete(urls),
                                   revealPath: urls.first?.path, blockedBy: blocked, group: "App- & Entwickler-Caches"))
        }

        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            items.append(CleanItem(id: "brew", title: "Homebrew – alte Versionen & Downloads",
                                   detail: "Führt „brew cleanup --prune=all“ aus", size: nil, selected: true,
                                   action: .command(brew, ["cleanup", "--prune=all"]),
                                   revealPath: Paths.expand("~/Library/Caches/Homebrew"), group: "App- & Entwickler-Caches"))
        }

        items += jetbrains()

        items.append(CleanItem(id: "trash", title: "Papierkorb leeren", detail: "Leert den Papierkorb über den Finder",
                               size: nil, selected: false, action: .emptyTrash, group: "Papierkorb"))

        // Größen parallel ermitteln
        let jobs: [(Int, [URL])] = items.enumerated().map { (i, it) in
            switch it.action {
            case .delete(let u): return (i, u)
            case .command: return (i, [URL(fileURLWithPath: Paths.expand("~/Library/Caches/Homebrew"))])
            case .emptyTrash: return (i, [URL(fileURLWithPath: Paths.expand("~/.Trash"))])
            case .docker: return (i, [])
            }
        }
        var sizes: [Int: Int64?] = [:]
        await withTaskGroup(of: (Int, Int64?).self) { g in
            for (i, urls) in jobs { g.addTask { (i, await Sizer.du(urls)) } }
            for await (i, s) in g { sizes[i] = s }
        }
        for i in items.indices { items[i].size = sizes[i] ?? nil }

        return items.filter { item in
            if item.id == "trash" { return (item.size ?? 1) > 0 }
            return (item.size ?? 0) > 1_000_000
        }
    }

    /// Caches/Logs alter JetBrains-IDE-Versionen (die neueste je Produkt bleibt)
    static func jetbrains() -> [CleanItem] {
        let bases: [(String, String, Bool)] = [
            ("~/Library/Caches/JetBrains", "Cache", true),
            ("~/Library/Logs/JetBrains", "Logs", true),
            ("~/Library/Application Support/JetBrains", "Einstellungen & Plugins", false),
        ]
        let rx = try! NSRegularExpression(pattern: #"^([A-Za-z]+)(\d{4})\.(\d+)$"#)
        func parse(_ name: String) -> (String, Int)? {
            let ns = name as NSString
            guard let m = rx.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let product = ns.substring(with: m.range(at: 1))
            let year = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let minor = Int(ns.substring(with: m.range(at: 3))) ?? 0
            return (product, year * 100 + minor)
        }
        var newest: [String: Int] = [:]
        for (b, _, _) in bases {
            for u in Paths.glob(b + "/*") {
                if let r = parse(u.lastPathComponent) { newest[r.0] = max(newest[r.0] ?? 0, r.1) }
            }
        }
        var res: [CleanItem] = []
        for (b, label, on) in bases {
            for u in Paths.glob(b + "/*") {
                guard let r = parse(u.lastPathComponent), let top = newest[r.0], r.1 < top else { continue }
                res.append(CleanItem(id: u.path, title: "\(u.lastPathComponent) – \(label)",
                                     detail: "Alte IDE-Version, aktuell ist \(r.0) \(top / 100).\(top % 100)",
                                     size: nil, selected: on, action: .delete([u]), revealPath: u.path,
                                     warning: on ? nil : "Nur löschen, wenn du diese Version nicht mehr brauchst",
                                     group: "Alte JetBrains-Versionen"))
            }
        }
        return res
    }
}

// MARK: - Entwicklung

enum DevScanner {
    static func scanDeps(root: URL, inactiveMonths: Int) async -> [CleanItem] {
        let args = [root.path, "-maxdepth", "6",
                    "(", "-name", ".git", "-o", "-name", ".ddev", "-o", "-name", "var", ")", "-prune", "-o",
                    "-type", "d", "(", "-name", "node_modules", "-o", "-name", "vendor", ")", "-prune", "-print"]
        let r = await Shell.run("/usr/bin/find", args, timeout: 300)
        let fm = FileManager.default
        var cands: [(URL, String)] = []
        for line in r.out.split(separator: "\n") {
            let u = URL(fileURLWithPath: String(line))
            let parent = u.deletingLastPathComponent()
            if u.lastPathComponent == "vendor", fm.fileExists(atPath: parent.appendingPathComponent("composer.lock").path) {
                cands.append((u, "composer install"))
            } else if u.lastPathComponent == "node_modules", fm.fileExists(atPath: parent.appendingPathComponent("package.json").path) {
                cands.append((u, "npm install"))
            }
        }
        let cutoff = Calendar.current.date(byAdding: .month, value: -inactiveMonths, to: Date()) ?? Date()
        let rootPath = root.path + "/"
        var items: [CleanItem] = []
        await withTaskGroup(of: CleanItem.self) { g in
            for (u, restore) in cands {
                g.addTask {
                    let size = await Sizer.du([u])
                    let project = u.deletingLastPathComponent()
                    let last = lastActivity(project)
                    let inactive = (last ?? .distantPast) < cutoff
                    let rel = project.path.replacingOccurrences(of: rootPath, with: "")
                    let nested = ["/custom/plugins/", "/custom/apps/", "/custom/static-plugins/"].contains { rel.contains($0) }
                    return CleanItem(id: u.path, title: rel,
                                     detail: "\(u.lastPathComponent) · Projekt zuletzt geändert: \(Fmt.date(last)) · wiederherstellbar mit „\(restore)“",
                                     size: size, selected: inactive && !nested, action: .delete([u]), revealPath: u.path,
                                     warning: nested ? "Gehört zu einem Shopware-Plugin/App – wird eventuell zur Laufzeit gebraucht" : nil,
                                     group: inactive ? "Abhängigkeiten ruhender Projekte (> \(inactiveMonths) Monate)" : "Abhängigkeiten aktiver Projekte")
                }
            }
            for await it in g { items.append(it) }
        }
        return items
            .filter { ($0.size ?? 0) > 20_000_000 }
            .sorted { a, b in
                if a.selected != b.selected { return a.selected }
                return (a.size ?? 0) > (b.size ?? 0)
            }
    }

    /// Neueste Änderung im Projekt – ohne Abhängigkeiten, Caches und Git
    static func lastActivity(_ dir: URL) -> Date? {
        let skip: Set<String> = ["vendor", "node_modules", ".git", "var", ".next", "public", "files", ".idea", "backup", ".ddev", "dist", "build"]
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsPackageDescendants]) else { return nil }
        var newest: Date?
        var count = 0
        while let obj = e.nextObject() {
            guard let u = obj as? URL else { continue }
            if e.level > 4 { e.skipDescendants(); continue }
            let name = u.lastPathComponent
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if v?.isDirectory == true {
                if skip.contains(name) { e.skipDescendants() }
                continue
            }
            if name == ".DS_Store" { continue }
            if let d = v?.contentModificationDate, d > (newest ?? .distantPast) { newest = d }
            count += 1
            if count > 30000 { break }
        }
        return newest
    }

    static func scanDumps(root: URL, progress: @escaping @Sendable (String) -> Void) async -> [CleanItem] {
        let args = [root.path, "(", "-name", "node_modules", "-o", "-name", "vendor", "-o", "-name", ".git", ")", "-prune", "-o",
                    "-type", "f", "(", "-iname", "*.sql", "-o", "-iname", "*.sql.gz", "-o", "-iname", "*.sql.zip", "-o", "-iname", "*.dump", ")",
                    "-size", "+100M", "-print"]
        let r = await Shell.run("/usr/bin/find", args, timeout: 600)
        struct F { let url: URL; let size: Int64; let date: Date? }
        var files: [F] = []
        for line in r.out.split(separator: "\n") {
            let u = URL(fileURLWithPath: String(line))
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            files.append(F(url: u, size: Int64(v?.fileSize ?? 0), date: v?.contentModificationDate))
        }
        let rootPath = root.path + "/"
        func rel(_ u: URL) -> String { u.path.replacingOccurrences(of: rootPath, with: "") }

        var items: [CleanItem] = []
        var dupPaths = Set<String>()
        let bySize = Dictionary(grouping: files, by: { $0.size })
        for (_, group) in bySize where group.count > 1 {
            var byHash: [String: [F]] = [:]
            for f in group {
                progress("Vergleiche \(f.url.lastPathComponent) (\(Fmt.bytes(f.size)))…")
                if let h = await Sizer.sha256Async(f.url) { byHash[h, default: []].append(f) }
            }
            for (_, same) in byHash where same.count > 1 {
                let sorted = same.sorted { ($0.url.path.count, $0.url.path) < ($1.url.path.count, $1.url.path) }
                let keep = sorted[0]
                for d in sorted.dropFirst() {
                    dupPaths.insert(d.url.path)
                    items.append(CleanItem(id: d.url.path, title: rel(d.url),
                                           detail: "Identisch mit \(rel(keep.url)) (SHA-256 geprüft) – das Original bleibt",
                                           size: d.size, selected: true, action: .delete([d.url]), revealPath: d.url.path,
                                           group: "Doppelte SQL-Dumps"))
                }
            }
        }
        for f in files.sorted(by: { $0.size > $1.size }) where !dupPaths.contains(f.url.path) && f.size > 1_000_000_000 {
            items.append(CleanItem(id: f.url.path, title: rel(f.url), detail: "Dump vom \(Fmt.date(f.date))",
                                   size: f.size, selected: false, action: .delete([f.url]), revealPath: f.url.path,
                                   warning: "Kein Duplikat – nur löschen, wenn du den Stand nicht mehr brauchst",
                                   group: "Große SQL-Dumps (> 1 GB) – selbst entscheiden"))
        }
        return items
    }
}

// MARK: - Docker

enum Docker {
    static var binary: String? {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let rawPath = "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    static func run(_ args: [String], timeout: TimeInterval = 120) async -> ShellResult {
        guard let b = binary else { return ShellResult(status: -1, out: "", err: "Docker ist nicht installiert") }
        return await Shell.run(b, args, timeout: timeout)
    }

    static func isRunning() async -> Bool {
        await run(["info", "--format", "{{.ServerVersion}}"], timeout: 20).status == 0
    }

    static func parseSize(_ s: String) -> Int64 {
        let t = s.split(separator: " ").first.map(String.init) ?? s
        let num = t.prefix { "0123456789.".contains($0) }
        let unit = t.dropFirst(num.count).uppercased()
        let v = Double(num) ?? 0
        let mult: [String: Double] = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12]
        return Int64(v * (mult[unit] ?? 1))
    }

    static func jsonLines(_ s: String) -> [[String: Any]] {
        s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    static func scan() async -> (summary: [String], items: [CleanItem]) {
        var summary: [String] = []
        var items: [CleanItem] = []

        // Überblick + Build-Cache
        let df = jsonLines(await run(["system", "df", "--format", "{{json .}}"]).out)
        let names = ["Images": "Images", "Containers": "Container", "Local Volumes": "Volumes", "Build Cache": "Build-Cache"]
        for row in df {
            let t = row["Type"] as? String ?? ""
            summary.append("\(names[t] ?? t): \(row["Size"] as? String ?? "–") · freigebbar \(row["Reclaimable"] as? String ?? "–")")
            if t == "Build Cache", let s = row["Size"] as? String, parseSize(s) > 0 {
                items.append(CleanItem(id: "buildcache", title: "Build-Cache", detail: "docker builder prune -a",
                                       size: parseSize(s), selected: true, action: .docker(["builder", "prune", "-a", "-f"]),
                                       group: "Build-Cache"))
            }
        }

        // Container
        let containers = jsonLines(await run(["ps", "-a", "-s", "--no-trunc", "--format", "{{json .}}"], timeout: 300).out)
        var usedImageIDs = Set<String>()
        let ids = containers.compactMap { $0["ID"] as? String }
        if !ids.isEmpty {
            let r = await run(["inspect", "--format", "{{.Image}}"] + ids)
            for l in r.out.split(separator: "\n") { usedImageIDs.insert(String(l)) }
        }
        for c in containers where (c["State"] as? String) != "running" {
            let id = c["ID"] as? String ?? ""
            let name = c["Names"] as? String ?? String(id.prefix(12))
            let img = c["Image"] as? String ?? ""
            items.append(CleanItem(id: "c-" + id, title: name, detail: "\(img) · \(c["Status"] as? String ?? "")",
                                   size: parseSize(c["Size"] as? String ?? "0B"), selected: false,
                                   action: .docker(["rm", id]),
                                   warning: "Code und Daten im Container gehen verloren (bei Dockware liegt der Shop im Container)",
                                   group: "Gestoppte Container"))
        }

        // Ungenutzte Images
        let imgs = jsonLines(await run(["images", "--digests", "--no-trunc", "--format", "{{json .}}"]).out)
        var seenRefs = Set<String>()
        for i in imgs {
            let id = i["ID"] as? String ?? ""
            guard !usedImageIDs.contains(id) else { continue }
            let repo = i["Repository"] as? String ?? "<none>"
            let tag = i["Tag"] as? String ?? "<none>"
            let digest = i["Digest"] as? String ?? "<none>"
            let dangling = repo == "<none>"
            let pulled = digest != "<none>" && !digest.isEmpty
            let shortID = String(id.replacingOccurrences(of: "sha256:", with: "").prefix(12))
            let name = dangling ? "<ohne Namen> \(shortID)" : "\(repo):\(tag)"
            let ref = (dangling || tag == "<none>") ? id : "\(repo):\(tag)"
            guard !seenRefs.contains(ref) else { continue }
            seenRefs.insert(ref)
            let how = pulled ? "kann per docker pull neu geladen werden" : (dangling ? "verwaistes Zwischen-Image" : "lokal gebaut")
            items.append(CleanItem(id: "i-" + ref, title: name, detail: "\(i["CreatedSince"] as? String ?? "") · \(how)",
                                   size: parseSize(i["Size"] as? String ?? "0B"), selected: pulled || dangling,
                                   action: .docker(["rmi", ref]),
                                   warning: (pulled || dangling) ? nil : "Lokal gebaut – nur per Neubau wiederherstellbar",
                                   group: "Ungenutzte Images"))
        }

        // Verwaiste Volumes
        let dangling = await run(["volume", "ls", "-f", "dangling=true", "--format", "{{.Name}}"]).out
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if !dangling.isEmpty {
            let v = await run(["system", "df", "-v"], timeout: 300).out
            var sizes: [String: Int64] = [:]
            var inVol = false
            for line in v.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("VOLUME NAME") { inVol = true; continue }
                guard inVol else { continue }
                if line.trimmingCharacters(in: .whitespaces).isEmpty { inVol = false; continue }
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 3 { sizes[String(parts[0])] = parseSize(String(parts[parts.count - 1])) }
            }
            for name in dangling.sorted() {
                items.append(CleanItem(id: "v-" + name, title: name, detail: "Volume, das an keinem Container hängt",
                                       size: sizes[name], selected: false, action: .docker(["volume", "rm", name]),
                                       warning: "Enthaltene Daten (z. B. Datenbanken) gehen verloren",
                                       group: "Verwaiste Volumes"))
            }
        }
        return (summary, items)
    }
}

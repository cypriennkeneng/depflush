import Foundation
import AppKit

// MARK: - Projektordner

enum ProjectRoots {
    static let candidates = ["~/Sites", "~/Projects", "~/projects", "~/Developer", "~/dev", "~/Dev", "~/code", "~/Code",
                             "~/workspace", "~/Workspace", "~/git", "~/src", "~/repos", "~/Documents/GitHub", "~/PhpstormProjects",
                             "~/WebstormProjects", "~/IdeaProjects", "~/Herd", "~/Valet"]

    static func detect() -> [String] {
        candidates.filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: Paths.expand($0), isDirectory: &d) && d.boolValue }
    }
}

// MARK: - Übersicht

enum OverviewScanner {
    static func scan(projectRoots: [String]) async -> [UsageRow] {
        var defs: [(String, String, String?, Pane?)] = [
            (L("Docker Desktop"), "~/Library/Containers/com.docker.docker", L("Images, Container und Volumes"), .docker),
            (L("Thunderbird-Mails"), "~/Library/Thunderbird", L("Offline-Kopie der Postfächer – in Thunderbird unter Konto → Synchronisation & Speicherplatz begrenzen"), nil),
            (L("Apple Mail"), "~/Library/Mail", nil, nil),
            (L("App-Caches"), "~/Library/Caches", L("Zwischenspeicher der Apps"), .caches),
            (L("WhatsApp-Medien"), "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared", L("In WhatsApp: Einstellungen → Speicher → große Dateien löschen"), nil),
            (L("Claude"), "~/Library/Application Support/Claude", nil, nil),
            (L("Chrome-Profil"), "~/Library/Application Support/Google", nil, nil),
            (L("Adobe"), "~/Library/Application Support/Adobe", nil, nil),
            (L("Slack"), "~/Library/Application Support/Slack", nil, nil),
            (L("Discord"), "~/Library/Application Support/discord", nil, nil),
            (L("Filme"), "~/Movies", nil, nil),
            (L("Downloads"), "~/Downloads", L("Selbst durchsehen – enthält oft persönliche Unterlagen"), nil),
            (L("Dokumente"), "~/Documents", nil, nil),
            (L("Schreibtisch"), "~/Desktop", nil, nil),
            (L("Bilder"), "~/Pictures", nil, nil),
            (L("iPhone-Backups"), "~/Library/Application Support/MobileSync/Backup", L("Finder → iPhone → Backups verwalten"), nil),
            (L("Xcode / Developer"), "~/Library/Developer", nil, nil),
            (L("npm-Cache"), "~/.npm", nil, .caches),
        ]
        for r in projectRoots {
            defs.append((L("Projekte (%@)", URL(fileURLWithPath: Paths.expand(r)).lastPathComponent), r, L("vendor/node_modules und SQL-Dumps"), .dev))
        }
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
    static var rules: [CacheRule] {
        let browser = L("Browser-Cache, baut sich automatisch neu auf")
        let web = L("Web-Cache der App (keine Chats, keine Anmeldung)")
        let pkg = L("Paket-Downloads, werden bei Bedarf neu geladen")
        let browsers = L("Heruntergeladene Test-Browser, werden bei Bedarf neu geladen")
        return [
            CacheRule(title: L("Google Chrome – Cache"), detail: browser, patterns: ["~/Library/Caches/Google"], bundleIDs: ["com.google.Chrome"], appName: "Google Chrome"),
            CacheRule(title: L("Firefox – Cache"), detail: browser, patterns: ["~/Library/Caches/Firefox", "~/Library/Caches/Mozilla"], bundleIDs: ["org.mozilla.firefox"], appName: "Firefox"),
            CacheRule(title: L("Brave – Cache"), detail: browser, patterns: ["~/Library/Caches/BraveSoftware"], bundleIDs: ["com.brave.Browser"], appName: "Brave"),
            CacheRule(title: L("Microsoft Edge – Cache"), detail: browser, patterns: ["~/Library/Caches/Microsoft Edge"], bundleIDs: ["com.microsoft.edgemac"], appName: "Microsoft Edge"),
            CacheRule(title: L("Arc – Cache"), detail: browser, patterns: ["~/Library/Caches/Arc"], bundleIDs: ["company.thebrowser.Browser"], appName: "Arc"),
            CacheRule(title: L("ChatGPT Atlas – Cache"), detail: browser, patterns: ["~/Library/Caches/com.openai.atlas"], bundleIDs: ["com.openai.atlas"], appName: "ChatGPT Atlas"),
            CacheRule(title: L("ChatGPT – Cache"), detail: web, patterns: ["~/Library/Caches/com.openai.chat"], bundleIDs: ["com.openai.chat"], appName: "ChatGPT"),
            CacheRule(title: L("Thunderbird – Cache"), detail: L("Nur der Cache, keine Mails"), patterns: ["~/Library/Caches/Thunderbird"], bundleIDs: ["org.mozilla.thunderbird"], appName: "Thunderbird"),
            CacheRule(title: L("WhatsApp – Cache"), detail: web, patterns: ["~/Library/Caches/net.whatsapp.WhatsApp"], bundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], appName: "WhatsApp"),
            CacheRule(title: L("CapCut – Cache"), detail: L("Vorschau-Cache, deine Projekte bleiben"), patterns: ["~/Movies/CapCut/User Data/Cache"], bundleIDs: ["com.lemon.lvoverseas"], appName: "CapCut"),
            CacheRule(title: L("Claude – Cache"), detail: web, patterns: ["~/Library/Application Support/Claude/Cache", "~/Library/Application Support/Claude/Code Cache"], bundleIDs: ["com.anthropic.claudefordesktop"], appName: "Claude"),
            CacheRule(title: L("Slack – Cache"), detail: web, patterns: ["~/Library/Application Support/Slack/Cache", "~/Library/Application Support/Slack/Code Cache", "~/Library/Application Support/Slack/Service Worker/CacheStorage"], bundleIDs: ["com.tinyspeck.slackmacgap"], appName: "Slack"),
            CacheRule(title: L("Discord – Cache"), detail: web, patterns: ["~/Library/Application Support/discord/Cache", "~/Library/Application Support/discord/Code Cache"], bundleIDs: ["com.hnc.Discord"], appName: "Discord"),
            CacheRule(title: L("VS Code – Cache"), detail: web, patterns: ["~/Library/Application Support/Code/Cache", "~/Library/Application Support/Code/CachedData", "~/Library/Application Support/Code/CachedExtensionVSIXs"], bundleIDs: ["com.microsoft.VSCode"], appName: "VS Code"),
            CacheRule(title: L("Cursor – Cache"), detail: web, patterns: ["~/Library/Application Support/Cursor/Cache", "~/Library/Application Support/Cursor/CachedData"], bundleIDs: ["com.todesktop.230313mzl4w4u92"], appName: "Cursor"),
            CacheRule(title: L("npm – Cache"), detail: L("Entspricht „npm cache clean --force“"), patterns: ["~/.npm/_cacache"]),
            CacheRule(title: L("Composer – Cache"), detail: pkg, patterns: ["~/Library/Caches/composer", "~/.composer/cache", "~/.cache/composer"]),
            CacheRule(title: L("Yarn – Cache"), detail: pkg, patterns: ["~/Library/Caches/Yarn"]),
            CacheRule(title: L("pnpm – Store"), detail: pkg, patterns: ["~/Library/pnpm/store"]),
            CacheRule(title: L("pip – Cache"), detail: pkg, patterns: ["~/Library/Caches/pip"]),
            CacheRule(title: L("Go – Build-Cache"), detail: pkg, patterns: ["~/Library/Caches/go-build"]),
            CacheRule(title: L("Gradle – Cache"), detail: pkg, patterns: ["~/.gradle/caches"]),
            CacheRule(title: L("CocoaPods – Cache"), detail: pkg, patterns: ["~/Library/Caches/CocoaPods"]),
            CacheRule(title: L("Xcode – DerivedData"), detail: L("Build-Zwischenstände, werden beim nächsten Build neu erzeugt"), patterns: ["~/Library/Developer/Xcode/DerivedData"], bundleIDs: ["com.apple.dt.Xcode"], appName: "Xcode"),
            CacheRule(title: L("Puppeteer – Browser"), detail: browsers, patterns: ["~/.cache/puppeteer"]),
            CacheRule(title: L("Playwright – Browser"), detail: browsers, patterns: ["~/Library/Caches/ms-playwright"]),
            CacheRule(title: L("shopware-cli – Cache"), detail: L("Tool-Cache"), patterns: ["~/Library/Caches/shopware-cli"]),
            CacheRule(title: L("Java-/JetBrains-Crash-Dumps"), detail: L("Speicherabbilder nach Abstürzen (*.hprof, java_error_*.log)"), patterns: ["~/*.hprof", "~/java_error_in_*.log", "~/jbr_err_*.log"]),
            CacheRule(title: L("Absturzberichte"), detail: "~/Library/Logs/DiagnosticReports", patterns: ["~/Library/Logs/DiagnosticReports/*"]),
        ]
    }

    static func scan() async -> [CleanItem] {
        let running = await MainActor.run { Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }) }
        var items: [CleanItem] = []
        let group = L("App- & Entwickler-Caches")

        for r in rules {
            let urls = r.patterns.flatMap { Paths.glob($0) }
            guard !urls.isEmpty else { continue }
            let blocked = r.bundleIDs.contains(where: { running.contains($0) }) ? (r.appName ?? "App") : nil
            items.append(CleanItem(id: r.patterns.joined(), title: r.title, detail: r.detail, size: nil,
                                   selected: r.on && blocked == nil, action: .delete(urls),
                                   revealPath: urls.first?.path, blockedBy: blocked, group: group))
        }

        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            items.append(CleanItem(id: "brew", title: L("Homebrew – alte Versionen & Downloads"),
                                   detail: L("Führt „brew cleanup --prune=all“ aus"), size: nil, selected: true,
                                   action: .command(brew, ["cleanup", "--prune=all"]),
                                   revealPath: Paths.expand("~/Library/Caches/Homebrew"), group: group))
        }

        items += jetbrains()

        items.append(CleanItem(id: "trash", title: L("Papierkorb leeren"), detail: L("Leert den Papierkorb über den Finder"),
                               size: nil, selected: false, action: .emptyTrash, group: L("Papierkorb")))

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
            ("~/Library/Caches/JetBrains", L("Cache"), true),
            ("~/Library/Logs/JetBrains", L("Logs"), true),
            ("~/Library/Application Support/JetBrains", L("Einstellungen & Plugins"), false),
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
                                     detail: L("Alte IDE-Version, aktuell ist %@", "\(r.0) \(top / 100).\(top % 100)"),
                                     size: nil, selected: on, action: .delete([u]), revealPath: u.path,
                                     warning: on ? nil : L("Nur löschen, wenn du diese Version nicht mehr brauchst"),
                                     group: L("Alte JetBrains-Versionen")))
            }
        }
        return res
    }
}

// MARK: - Entwicklung

enum DevScanner {
    static func label(for root: URL, multi: Bool) -> String { multi ? root.lastPathComponent + "/" : "" }

    static func scanDeps(root: URL, multi: Bool, inactiveMonths: Int) async -> [CleanItem] {
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
        let prefix = label(for: root, multi: multi)
        let gInactive = L("Abhängigkeiten ruhender Projekte (> %d Monate)", inactiveMonths)
        let gActive = L("Abhängigkeiten aktiver Projekte")
        let pluginWarn = L("Gehört zu einem Plugin/Paket – wird eventuell zur Laufzeit gebraucht")
        var items: [CleanItem] = []
        await withTaskGroup(of: CleanItem.self) { g in
            for (u, restore) in cands {
                g.addTask {
                    let size = await Sizer.du([u])
                    let project = u.deletingLastPathComponent()
                    let last = lastActivity(project)
                    let inactive = (last ?? .distantPast) < cutoff
                    let rel = project.path.replacingOccurrences(of: rootPath, with: "")
                    let nested = ["/custom/plugins/", "/custom/apps/", "/custom/static-plugins/", "/packages/", "/plugins/"].contains { rel.contains($0) }
                    return CleanItem(id: u.path, title: prefix + rel,
                                     detail: L("%@ · Projekt zuletzt geändert: %@ · wiederherstellbar mit „%@“", u.lastPathComponent, Fmt.date(last), restore),
                                     size: size, selected: inactive && !nested, action: .delete([u]), revealPath: u.path,
                                     warning: nested ? pluginWarn : nil,
                                     group: inactive ? gInactive : gActive)
                }
            }
            for await it in g { items.append(it) }
        }
        return items.filter { ($0.size ?? 0) > 20_000_000 }
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

    static func scanDumps(roots: [URL], progress: @escaping @Sendable (String) -> Void) async -> [CleanItem] {
        struct F { let url: URL; let size: Int64; let date: Date?; let rel: String }
        var files: [F] = []
        let multi = roots.count > 1
        for root in roots {
            let args = [root.path, "(", "-name", "node_modules", "-o", "-name", "vendor", "-o", "-name", ".git", ")", "-prune", "-o",
                        "-type", "f", "(", "-iname", "*.sql", "-o", "-iname", "*.sql.gz", "-o", "-iname", "*.sql.zip", "-o", "-iname", "*.dump", ")",
                        "-size", "+100M", "-print"]
            let r = await Shell.run("/usr/bin/find", args, timeout: 600)
            let rootPath = root.path + "/"
            let prefix = label(for: root, multi: multi)
            for line in r.out.split(separator: "\n") {
                let u = URL(fileURLWithPath: String(line))
                let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                files.append(F(url: u, size: Int64(v?.fileSize ?? 0), date: v?.contentModificationDate,
                               rel: prefix + u.path.replacingOccurrences(of: rootPath, with: "")))
            }
        }

        var items: [CleanItem] = []
        var dupPaths = Set<String>()
        let gDup = L("Doppelte SQL-Dumps")
        for (_, group) in Dictionary(grouping: files, by: { $0.size }) where group.count > 1 {
            var byHash: [String: [F]] = [:]
            for f in group {
                progress(L("Vergleiche %@ (%@) …", f.url.lastPathComponent, Fmt.bytes(f.size)))
                if let h = await Sizer.sha256Async(f.url) { byHash[h, default: []].append(f) }
            }
            for (_, same) in byHash where same.count > 1 {
                let sorted = same.sorted { ($0.url.path.count, $0.url.path) < ($1.url.path.count, $1.url.path) }
                let keep = sorted[0]
                for d in sorted.dropFirst() {
                    dupPaths.insert(d.url.path)
                    items.append(CleanItem(id: d.url.path, title: d.rel,
                                           detail: L("Identisch mit %@ (SHA-256 geprüft) – das Original bleibt", keep.rel),
                                           size: d.size, selected: true, action: .delete([d.url]), revealPath: d.url.path,
                                           group: gDup))
                }
            }
        }
        let gBig = L("Große SQL-Dumps (> 1 GB) – selbst entscheiden")
        for f in files.sorted(by: { $0.size > $1.size }) where !dupPaths.contains(f.url.path) && f.size > 1_000_000_000 {
            items.append(CleanItem(id: f.url.path, title: f.rel, detail: L("Dump vom %@", Fmt.date(f.date)),
                                   size: f.size, selected: false, action: .delete([f.url]), revealPath: f.url.path,
                                   warning: L("Kein Duplikat – nur löschen, wenn du den Stand nicht mehr brauchst"),
                                   group: gBig))
        }
        return items
    }
}

// MARK: - Docker

enum Docker {
    static var binary: String? {
        ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker", Paths.expand("~/.docker/bin/docker"), Paths.expand("~/.orbstack/bin/docker")]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let rawPath = "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    static func run(_ args: [String], timeout: TimeInterval = 120) async -> ShellResult {
        guard let b = binary else { return ShellResult(status: -1, out: "", err: L("Docker ist nicht installiert")) }
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

        let df = jsonLines(await run(["system", "df", "--format", "{{json .}}"]).out)
        let names = ["Images": L("Images"), "Containers": L("Container"), "Local Volumes": L("Volumes"), "Build Cache": L("Build-Cache")]
        for row in df {
            let t = row["Type"] as? String ?? ""
            summary.append(L("%@: %@ · freigebbar %@", names[t] ?? t, row["Size"] as? String ?? "–", row["Reclaimable"] as? String ?? "–"))
            if t == "Build Cache", let s = row["Size"] as? String, parseSize(s) > 0 {
                items.append(CleanItem(id: "buildcache", title: L("Build-Cache"), detail: "docker builder prune -a",
                                       size: parseSize(s), selected: true, action: .docker(["builder", "prune", "-a", "-f"]),
                                       group: L("Build-Cache")))
            }
        }

        let containers = jsonLines(await run(["ps", "-a", "-s", "--no-trunc", "--format", "{{json .}}"], timeout: 300).out)
        var usedImageIDs = Set<String>()
        let ids = containers.compactMap { $0["ID"] as? String }
        if !ids.isEmpty {
            let r = await run(["inspect", "--format", "{{.Image}}"] + ids)
            for l in r.out.split(separator: "\n") { usedImageIDs.insert(String(l)) }
        }
        let gCont = L("Gestoppte Container")
        let contWarn = L("Code und Daten im Container gehen verloren (z. B. liegt bei Dockware der Shop im Container)")
        for c in containers where (c["State"] as? String) != "running" {
            let id = c["ID"] as? String ?? ""
            let name = c["Names"] as? String ?? String(id.prefix(12))
            let img = c["Image"] as? String ?? ""
            items.append(CleanItem(id: "c-" + id, title: name, detail: "\(img) · \(c["Status"] as? String ?? "")",
                                   size: parseSize(c["Size"] as? String ?? "0B"), selected: false,
                                   action: .docker(["rm", id]), warning: contWarn, group: gCont))
        }

        let imgs = jsonLines(await run(["images", "--digests", "--no-trunc", "--format", "{{json .}}"]).out)
        var seenRefs = Set<String>()
        let gImg = L("Ungenutzte Images")
        for i in imgs {
            let id = i["ID"] as? String ?? ""
            guard !usedImageIDs.contains(id) else { continue }
            let repo = i["Repository"] as? String ?? "<none>"
            let tag = i["Tag"] as? String ?? "<none>"
            let digest = i["Digest"] as? String ?? "<none>"
            let dangling = repo == "<none>"
            let pulled = digest != "<none>" && !digest.isEmpty
            let shortID = String(id.replacingOccurrences(of: "sha256:", with: "").prefix(12))
            let name = dangling ? L("<ohne Namen> %@", shortID) : "\(repo):\(tag)"
            let ref = (dangling || tag == "<none>") ? id : "\(repo):\(tag)"
            guard !seenRefs.contains(ref) else { continue }
            seenRefs.insert(ref)
            let how = pulled ? L("kann per docker pull neu geladen werden") : (dangling ? L("verwaistes Zwischen-Image") : L("lokal gebaut"))
            items.append(CleanItem(id: "i-" + ref, title: name, detail: "\(i["CreatedSince"] as? String ?? "") · \(how)",
                                   size: parseSize(i["Size"] as? String ?? "0B"), selected: pulled || dangling,
                                   action: .docker(["rmi", ref]),
                                   warning: (pulled || dangling) ? nil : L("Lokal gebaut – nur per Neubau wiederherstellbar"),
                                   group: gImg))
        }

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
            let gVol = L("Verwaiste Volumes")
            for name in dangling.sorted() {
                items.append(CleanItem(id: "v-" + name, title: name, detail: L("Volume, das an keinem Container hängt"),
                                       size: sizes[name], selected: false, action: .docker(["volume", "rm", name]),
                                       warning: L("Enthaltene Daten (z. B. Datenbanken) gehen verloren"),
                                       group: gVol))
            }
        }
        return (summary, items)
    }
}

import Foundation

// MARK: - Doppelte Dateien (Fotos, Videos, optional alle Dateien)

enum DuplicateScanner {
    static let defaultRoots = ["~/Pictures", "~/Movies", "~/Documents", "~/Desktop", "~/Downloads"]

    static let imageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp", "psd", "svg",
                                        "raw", "dng", "cr2", "cr3", "nef", "arw", "orf", "raf", "rw2", "avif"]
    static let videoExt: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mts", "m2ts", "3gp", "wmv", "flv", "mpg", "mpeg"]

    /// Bibliotheken und Pakete, in die nie hineingeschaut wird (Fotos-Mediathek, iMovie, Final Cut, Lightroom, Apps …)
    static let pruneNames = ["*.photoslibrary", "*.photolibrary", "*.migratedphotolibrary", "*.aplibrary", "*.imovielibrary",
                             "*.theater", "*.fcpbundle", "*.lrdata", "*.lrlibrary", "*.cocatalog", "*.cocatalogdb", "*.logicx", "*.band",
                             "*.musiclibrary", "*.tvlibrary", "*.app", "*.bundle", "*.framework", "*.xcarchive",
                             "*.localized", "*.sparsebundle", "*.pvm", "*.utm", "*.vmwarevm",
                             "Photo Booth Library", "node_modules", "vendor", "Library",
                             // Arbeitsdaten von Apps (Projekte, Vorlagen, Caches) – Löschen würde Projekte beschädigen
                             "CapCut", "JianyingPro", "User Data", "TV", "Music", "Caches", "Cache", "DaVinci Resolve",
                             "Blackmagic Design", "Adobe", "Microsoft User Data", "Zoom", "OBS", "Camtasia", "ScreenFlow"]

    struct F {
        let path: String
        let size: Int64
        let birth: Date
        var url: URL { URL(fileURLWithPath: path) }
    }

    static func category(_ path: String) -> Int {
        let e = (path as NSString).pathExtension.lowercased()
        if imageExt.contains(e) { return 0 }
        if videoExt.contains(e) { return 1 }
        return 2
    }

    static func groupTitle(_ c: Int) -> String {
        switch c {
        case 0: return L("Fotos & Bilder")
        case 1: return L("Videos")
        case 3: return L("In App-Ordnern – selbst entscheiden")
        default: return L("Andere Dateien")
        }
    }

    /// Kopien-Endungen wie „Bild Kopie.jpg“, „Bild copy 2.jpg“, „Bild (1).jpg“
    static func looksLikeCopy(_ path: String) -> Bool {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return stem.range(of: #"(?i)(\s(copy|kopie|copie)(\s\d+)?|\s?\(\d+\)|\s-\s(copy|kopie|copie)(\s\d+)?)$"#,
                          options: .regularExpression) != nil
    }

    /// Pfade, die nach von einer App verwalteten Dateien aussehen (Hash-/UUID-Ordner, Entwürfe)
    static func looksAppManaged(_ path: String) -> Bool {
        let rel = path.hasPrefix(Paths.home) ? String(path.dropFirst(Paths.home.count)) : path
        let comps = rel.split(separator: "/").map(String.init)
        for c in comps {
            let stem = (c as NSString).deletingPathExtension
            if stem.range(of: #"[0-9A-Fa-f]{16,}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}"#, options: .regularExpression) != nil { return true }
            if c.contains("##") || c.lowercased().contains(".draft") { return true }
        }
        return false
    }

    /// Je kleiner, desto eher ist die Datei das Original
    static func locationRank(_ path: String) -> Int {
        let home = Paths.home
        if path.hasPrefix(home + "/Pictures/") || path.hasPrefix(home + "/Movies/") { return 0 }
        if path.hasPrefix(home + "/Documents/") { return 1 }
        if path.hasPrefix(home + "/Desktop/") { return 2 }
        if path.hasPrefix(home + "/Downloads/") { return 3 }
        return 1
    }

    static func keepFirst(_ a: F, _ b: F) -> Bool {
        let la = locationRank(a.path), lb = locationRank(b.path)
        if la != lb { return la < lb }
        let ca = looksLikeCopy(a.path), cb = looksLikeCopy(b.path)
        if ca != cb { return !ca }
        if a.birth != b.birth { return a.birth < b.birth }
        return (a.path.count, a.path) < (b.path.count, b.path)
    }

    static func scan(roots: [String], allFiles: Bool, exclude: [String],
                     progress: @escaping @Sendable (String) -> Void) async -> [CleanItem] {
        let minKB = allFiles ? 1024 : 100
        var files: [F] = []
        var seenInode = Set<String>()
        var seenRoot = Set<String>()

        for r in roots {
            let root = URL(fileURLWithPath: Paths.expand(r)).resolvingSymlinksInPath().path
            var isDir: ObjCBool = false
            guard seenRoot.insert(root).inserted,
                  FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            progress(L("Durchsuche %@ …", Paths.tilde(root)))

            var prune: [String] = ["-name", ".*"]
            for n in pruneNames { prune += ["-o", "-name", n] }
            for p in exclude where p.hasPrefix(root + "/") { prune += ["-o", "-path", p] }
            let args = [root + "/", "(", "-type", "d", "("] + prune + [")", ")", "-prune", "-o",
                        "-type", "f", "-size", "+\(minKB)k", "!", "-name", ".*", "-print0"]
            let res = await Shell.run("/usr/bin/find", args, timeout: 900)

            for line in res.out.split(separator: "\0") {
                let path = String(line).replacingOccurrences(of: "//", with: "/")
                if !allFiles && category(path) == 2 { continue }
                var st = stat()
                guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
                if st.st_flags & 0x40000000 != 0 { continue }            // SF_DATALESS: liegt nur in iCloud – nicht herunterladen
                guard seenInode.insert("\(st.st_dev):\(st.st_ino)").inserted else { continue }   // Hardlink / doppelt gescannt
                files.append(F(path: path, size: Int64(st.st_size),
                               birth: Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec) + TimeInterval(st.st_birthtimespec.tv_nsec) / 1e9)))
            }
        }

        // 1. gleiche Größe → 2. Anfang/Ende gleich → 3. SHA-256 über die ganze Datei
        let bySize = Dictionary(grouping: files, by: \.size).filter { $0.value.count > 1 }
        let total = bySize.values.reduce(0) { $0 + $1.count }
        var checked = 0
        var sets: [[F]] = []
        for (_, group) in bySize.sorted(by: { $0.key > $1.key }) {
            var byQuick: [String: [F]] = [:]
            for f in group {
                checked += 1
                if checked % 10 == 1 { progress(L("Vergleiche Dateien … %d von %d", checked, total)) }
                if let h = await Sizer.quickHashAsync(f.url) { byQuick[h, default: []].append(f) }
            }
            for (_, cand) in byQuick where cand.count > 1 {
                var byFull: [String: [F]] = [:]
                for f in cand {
                    if f.size > 200_000_000 { progress(L("Vergleiche %@ (%@) …", f.url.lastPathComponent, Fmt.bytes(f.size))) }
                    if let h = await Sizer.sha256Async(f.url) { byFull[h, default: []].append(f) }
                }
                for (_, same) in byFull where same.count > 1 { sets.append(same) }
            }
        }

        var items: [(Int, CleanItem)] = []
        for set in sets {
            let sorted = set.sorted(by: keepFirst)
            let keep = sorted[0]
            for d in sorted.dropFirst() {
                // APFS-Klone teilen sich den Speicher: Löschen brächte (fast) nichts
                let freed = FileInfo.privateSize(d.path) ?? d.size
                guard freed > d.size / 10 else { continue }
                let appData = looksAppManaged(d.path) || looksAppManaged(keep.path)
                let c = appData ? 3 : category(d.path)
                items.append((c, CleanItem(id: "dup:" + d.path, title: Paths.tilde(d.path),
                                           detail: L("Identisch mit %@ – das Original bleibt", Paths.tilde(keep.path)),
                                           size: freed, selected: !appData,
                                           action: .deleteCopy(d.url, original: keep.url, size: d.size),
                                           revealPath: d.path,
                                           warning: appData ? L("Sieht nach Arbeitsdaten einer App aus – nur löschen, wenn du dir sicher bist") : nil,
                                           group: groupTitle(c))))
            }
        }
        return items.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : ($0.1.size ?? 0) > ($1.1.size ?? 0) }.map(\.1)
    }
}

enum FileInfo {
    /// Platz, den nur diese Datei belegt (APFS: ohne mit Klonen geteilte Blöcke); nil = unbekannt
    static func privateSize(_ path: String) -> Int64? {
        var al = attrlist()
        al.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        al.commonattr = attrgroup_t(0x8000_0000)          // ATTR_CMN_RETURNED_ATTRS
        al.forkattr = attrgroup_t(0x0000_0008)            // ATTR_CMNEXT_PRIVATESIZE
        var buf = [UInt8](repeating: 0, count: 64)
        let opts = UInt32(0x20 | 0x1)                     // FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW
        guard getattrlist(path, &al, &buf, buf.count, opts) == 0 else { return nil }
        return buf.withUnsafeBytes { p -> Int64? in
            let set = p.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            guard set.forkattr & 0x8 != 0 else { return nil }
            return p.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attribute_set_t>.size, as: Int64.self)
        }
    }

    static func size(_ path: String) -> Int64? {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int64(st.st_size)
    }
}

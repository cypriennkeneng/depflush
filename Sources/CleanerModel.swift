import Foundation
import AppKit
import UserNotifications

// MARK: - Speicher-Monitor (Menüleiste + Warnung)

@MainActor
final class DiskMonitor: ObservableObject {
    static let shared = DiskMonitor()

    @Published var free: Int64 = 0
    @Published var total: Int64 = 0
    private var timer: Timer?
    private var warned = false

    var thresholdGB: Int {
        let v = UserDefaults.standard.integer(forKey: "warnGB")
        return v > 0 ? v : 20
    }
    var isLow: Bool { total > 0 && free < Int64(thresholdGB) * 1_000_000_000 }
    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }

    nonisolated static func current() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        return (Int64(v?.volumeAvailableCapacity ?? 0), Int64(v?.volumeTotalCapacity ?? 0))
    }

    func start() {
        refresh()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in DiskMonitor.shared.refresh() }
        }
    }

    func refresh() {
        let c = Self.current()
        free = c.free
        total = c.total
        if isLow && !warned {
            warned = true
            notify()
        } else if !isLow {
            warned = false
        }
    }

    private func notify() {
        let c = UNMutableNotificationContent()
        c.title = "Speicher fast voll"
        c.body = "Nur noch \(Fmt.bytes(free)) frei. Öffne den Aufräumer, um Platz zu schaffen."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowdisk-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
    }
}

// MARK: - Haupt-Modell

@MainActor
final class CleanerModel: ObservableObject {
    static let shared = CleanerModel()

    enum DockerState { case unknown, notInstalled, stopped, starting, running }

    @Published var overview: [UsageRow] = []
    @Published var swap: Int64?
    @Published var caches: [CleanItem] = []
    @Published var dev: [CleanItem] = []
    @Published var docker: [CleanItem] = []
    @Published var dockerSummary: [String] = []
    @Published var dockerRaw: Int64?
    @Published var dockerState: DockerState = .unknown
    @Published var busy: Set<Pane> = []
    @Published var status: String = ""
    @Published var lastScan: [Pane: Date] = [:]
    @Published var history: [HistoryEntry] = []
    @Published var resultMessage: String?

    var projectRoot: String { UserDefaults.standard.string(forKey: "projectRoot") ?? "~/Sites" }
    var inactiveMonths: Int {
        let v = UserDefaults.standard.integer(forKey: "inactiveMonths")
        return v > 0 ? v : 12
    }

    init() { loadHistory() }

    // MARK: Items

    func items(for pane: Pane) -> [CleanItem] {
        switch pane {
        case .caches: return caches
        case .dev: return dev
        case .docker: return docker
        default: return []
        }
    }

    func setItems(_ items: [CleanItem], for pane: Pane) {
        switch pane {
        case .caches: caches = items
        case .dev: dev = items
        case .docker: docker = items
        default: break
        }
    }

    func toggle(_ id: String, in pane: Pane, _ value: Bool) {
        var arr = items(for: pane)
        if let i = arr.firstIndex(where: { $0.id == id }) {
            arr[i].selected = value
            setItems(arr, for: pane)
        }
    }

    func setAll(_ value: Bool, in pane: Pane, group: String) {
        var arr = items(for: pane)
        for i in arr.indices where arr[i].group == group && arr[i].blockedBy == nil { arr[i].selected = value }
        setItems(arr, for: pane)
    }

    func selectedSize(_ pane: Pane) -> Int64 {
        items(for: pane).filter(\.isActive).reduce(0) { $0 + ($1.size ?? 0) }
    }

    func selectedCount(_ pane: Pane) -> Int { items(for: pane).filter(\.isActive).count }

    var totalSelected: Int64 { selectedSize(.caches) + selectedSize(.dev) + selectedSize(.docker) }

    func selectedSummary(_ pane: Pane) -> String {
        let sel = items(for: pane).filter(\.isActive)
        var lines = sel.prefix(10).map { "• \($0.title) (\(Fmt.bytes($0.size)))" }
        if sel.count > 10 { lines.append("… und \(sel.count - 10) weitere") }
        return lines.joined(separator: "\n") + "\n\nDas kann nicht rückgängig gemacht werden."
    }

    // MARK: Scannen

    func scanAll() async {
        async let a: Void = scan(.overview)
        async let b: Void = scan(.caches)
        _ = await (a, b)
    }

    func scan(_ pane: Pane) async {
        guard !busy.contains(pane) else { return }
        busy.insert(pane)
        defer { busy.remove(pane); if busy.isEmpty { status = "" } }
        switch pane {
        case .overview:
            status = "Analysiere Speicher…"
            overview = await OverviewScanner.scan(projectRoot: projectRoot)
            swap = await OverviewScanner.swap()
        case .caches:
            status = "Suche Caches…"
            caches = await CacheScanner.scan()
        case .dev:
            let root = URL(fileURLWithPath: Paths.expand(projectRoot))
            status = "Suche vendor- und node_modules-Ordner…"
            var d = await DevScanner.scanDeps(root: root, inactiveMonths: inactiveMonths)
            status = "Suche SQL-Dumps…"
            d += await DevScanner.scanDumps(root: root) { s in
                Task { @MainActor in CleanerModel.shared.status = s }
            }
            dev = d
        case .docker:
            await scanDocker()
        default:
            break
        }
        lastScan[pane] = Date()
        DiskMonitor.shared.refresh()
    }

    private func scanDocker() async {
        guard Docker.binary != nil else { dockerState = .notInstalled; docker = []; return }
        status = "Prüfe Docker…"
        guard await Docker.isRunning() else { dockerState = .stopped; docker = []; return }
        dockerState = .running
        status = "Lese Images, Container und Volumes…"
        let r = await Docker.scan()
        dockerSummary = r.summary
        docker = r.items
        dockerRaw = await Sizer.du([URL(fileURLWithPath: Paths.expand(Docker.rawPath))])
    }

    func startDocker() {
        dockerState = .starting
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Docker.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        Task {
            for _ in 0..<45 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if await Docker.isRunning() { break }
            }
            await scan(.docker)
        }
    }

    // MARK: Bereinigen

    private func priority(_ i: CleanItem) -> Int {
        if case .docker(let a) = i.action {
            switch a.first {
            case "rm": return 0
            case "volume": return 1
            case "rmi": return 2
            default: return 3
            }
        }
        return 0
    }

    func clean(_ pane: Pane) async {
        let selected = items(for: pane).filter(\.isActive).sorted { priority($0) < priority($1) }
        guard !selected.isEmpty, !busy.contains(pane) else { return }
        busy.insert(pane)
        let before = DiskMonitor.current().free
        var errors: [String] = []
        var done: [String] = []
        var estimated: Int64 = 0
        let protectedRoots = [Paths.expand(projectRoot)]
        for (n, item) in selected.enumerated() {
            status = "(\(n + 1)/\(selected.count)) Entferne \(item.title)…"
            do {
                try await Executor.run(item.action, extraProtected: protectedRoots)
                done.append(item.title)
                estimated += item.size ?? 0
            } catch {
                errors.append("\(item.title): \(error.localizedDescription)")
            }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let measured = max(0, DiskMonitor.current().free - before)
        if !done.isEmpty {
            history.insert(HistoryEntry(date: Date(), area: pane.title, items: done, estimated: estimated, measured: measured), at: 0)
            saveHistory()
        }
        var msg = "\(done.count) von \(selected.count) Elementen entfernt.\nFreigegeben: ca. \(Fmt.bytes(estimated))"
        if measured > 0 { msg += " (sofort messbar: \(Fmt.bytes(measured)))" }
        if pane == .docker { msg += "\n\nDocker gibt den Platz teils verzögert an macOS zurück." }
        if !errors.isEmpty { msg += "\n\nNicht möglich:\n" + errors.prefix(6).joined(separator: "\n") }
        busy.remove(pane)
        status = ""
        DiskMonitor.shared.refresh()
        resultMessage = msg
        await scan(pane)
        await scan(.overview)
    }

    // MARK: Verlauf

    private var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aufraeumer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("verlauf.json")
    }

    private func loadHistory() {
        guard let d = try? Data(contentsOf: historyURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        history = (try? dec.decode([HistoryEntry].self, from: d)) ?? []
    }

    private func saveHistory() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        if let d = try? enc.encode(history) { try? d.write(to: historyURL) }
    }
}

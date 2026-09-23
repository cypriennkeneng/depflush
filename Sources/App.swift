import SwiftUI
import AppKit

@main
struct DepflushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = CleanerModel.shared
    @StateObject private var disk = DiskMonitor.shared

    init() {
        Migration.fromAufraeumer()
        UserDefaults.standard.register(defaults: [
            "inactiveMonths": 12,
            "useTrash": true,
            "language": "system",
            "warnGB": 20,
        ])
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(disk)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
                .environmentObject(disk)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in DiskMonitor.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Übernimmt Einstellungen und Verlauf der Vorgängerversion „Aufräumer“ (de.webloupe.aufraeumer)
enum Migration {
    static func fromAufraeumer() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromAufraeumer") else { return }
        d.set(true, forKey: "migratedFromAufraeumer")
        let own = d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        if let old = UserDefaults(suiteName: "de.webloupe.aufraeumer") {
            for k in ["projectRoots", "projectRoot", "inactiveMonths", "warnGB", "useTrash", "language", "welcomeShown"]
            where own[k] == nil {
                if let v = old.object(forKey: k) { d.set(v, forKey: k) }
            }
        }
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFile = base.appendingPathComponent("Aufraeumer/verlauf.json")
        let newDir = base.appendingPathComponent("Depflush")
        let newFile = newDir.appendingPathComponent("verlauf.json")
        if fm.fileExists(atPath: oldFile.path) && !fm.fileExists(atPath: newFile.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            try? fm.copyItem(at: oldFile, to: newFile)
        }
    }
}

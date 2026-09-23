import SwiftUI
import AppKit

@main
struct AufraeumerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = CleanerModel.shared
    @StateObject private var disk = DiskMonitor.shared

    init() {
        UserDefaults.standard.register(defaults: [
            "projectRoot": "~/Sites",
            "inactiveMonths": 12,
            "warnGB": 20,
        ])
    }

    var body: some Scene {
        Window("Aufräumer", id: "main") {
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

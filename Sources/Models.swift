import Foundation
import AppKit

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case overview, caches, dev, docker, history, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Übersicht")
        case .caches: return L("Caches")
        case .dev: return L("Entwicklung")
        case .docker: return L("Docker")
        case .history: return L("Verlauf")
        case .settings: return L("Einstellungen")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .caches: return "sparkles"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .docker: return "shippingbox"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

enum CleanAction {
    case delete([URL])
    case command(String, [String])
    case docker([String])
    case emptyTrash

    var isFileDelete: Bool { if case .delete = self { return true } else { return false } }
}

struct CleanItem: Identifiable {
    let id: String
    var title: String
    var detail: String
    var size: Int64?
    var selected: Bool
    var action: CleanAction
    var revealPath: String? = nil
    var blockedBy: String? = nil
    var warning: String? = nil
    var group: String = ""

    var isActive: Bool { selected && blockedBy == nil }
}

struct UsageRow: Identifiable {
    var id: String { (path ?? "") + title }
    let title: String
    let path: String?
    let size: Int64?
    let hint: String?
    let pane: Pane?
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let area: String
    let items: [String]
    let estimated: Int64
    let measured: Int64
    var toTrash: Bool? = nil
}

enum CleanError: LocalizedError {
    case blocked(String)
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .blocked(let p): return L("Geschützter Pfad, nicht gelöscht: %@", p)
        case .failed(let m): return m.isEmpty ? L("Unbekannter Fehler") : m
        }
    }
}

enum Executor {
    static func run(_ action: CleanAction, extraProtected: [String], useTrash: Bool) async throws {
        switch action {
        case .delete(let urls):
            for u in urls {
                let fm = FileManager.default
                let isLink = (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
                guard fm.fileExists(atPath: u.path) || isLink else { continue }
                guard Safety.isAllowed(u, extraProtected: extraProtected) else {
                    throw CleanError.blocked(Paths.tilde(u.path))
                }
                if useTrash {
                    let err: String? = await withCheckedContinuation { c in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil); c.resume(returning: nil) }
                            catch { c.resume(returning: error.localizedDescription) }
                        }
                    }
                    if let err { throw CleanError.failed(err) }
                } else {
                    let r = await Shell.run("/bin/rm", ["-rf", "--", u.path], timeout: 3600)
                    if r.status != 0 {
                        throw CleanError.failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        case .command(let exe, let args):
            let r = await Shell.run(exe, args, timeout: 1800)
            if r.status != 0 { throw CleanError.failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .docker(let args):
            let r = await Docker.run(args, timeout: 1800)
            if r.status != 0 { throw CleanError.failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .emptyTrash:
            let ok = await MainActor.run { () -> Bool in
                var err: NSDictionary?
                NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
                return err == nil
            }
            if !ok {
                throw CleanError.failed(L("Papierkorb konnte nicht geleert werden – bitte in Systemeinstellungen → Datenschutz → Automation den Finder erlauben."))
            }
        }
    }
}

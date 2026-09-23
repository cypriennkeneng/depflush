import Foundation
import AppKit
import CryptoKit

// MARK: - Shell

struct ShellResult {
    let status: Int32
    let out: String
    let err: String
}

final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _out = Data()
    private var _err = Data()
    var out: Data { lock.lock(); defer { lock.unlock() }; return _out }
    var err: Data { lock.lock(); defer { lock.unlock() }; return _err }
    func setOut(_ d: Data) { lock.lock(); _out = d; lock.unlock() }
    func setErr(_ d: Data) { lock.lock(); _err = d; lock.unlock() }
}

enum Shell {
    static let path = "/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 120) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(exe, args, timeout: timeout))
            }
        }
    }

    static func runSync(_ exe: String, _ args: [String], timeout: TimeInterval) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        p.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return ShellResult(status: -1, out: "", err: error.localizedDescription)
        }
        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { box.setOut(outPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter()
        DispatchQueue.global().async { box.setErr(errPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        group.wait()
        return ShellResult(status: p.terminationStatus,
                           out: String(decoding: box.out, as: UTF8.self),
                           err: String(decoding: box.err, as: UTF8.self))
    }
}

// MARK: - Paths

enum Paths {
    static let home = NSHomeDirectory()

    static func expand(_ p: String) -> String {
        p.hasPrefix("~") ? home + String(p.dropFirst()) : p
    }

    static func tilde(_ p: String) -> String {
        p.hasPrefix(home) ? "~" + String(p.dropFirst(home.count)) : p
    }

    static func glob(_ pattern: String) -> [URL] {
        var g = glob_t()
        defer { globfree(&g) }
        guard Darwin.glob(expand(pattern), 0, nil, &g) == 0 else { return [] }
        var res: [URL] = []
        for i in 0..<Int(g.gl_pathc) {
            if let c = g.gl_pathv[i] { res.append(URL(fileURLWithPath: String(cString: c))) }
        }
        return res
    }
}

// MARK: - Größen

enum Sizer {
    /// Belegter Platz (wie `du -sk`), nil wenn nichts existiert/lesbar ist
    static func du(_ urls: [URL]) async -> Int64? {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }
        let r = await Shell.run("/usr/bin/du", ["-sk"] + existing.map { $0.path }, timeout: 600)
        var total: Int64 = 0
        var any = false
        for line in r.out.split(separator: "\n") {
            let first = line.split(separator: "\t").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            if let k = Int64(first) { total += k * 1024; any = true }
        }
        return any ? total : nil
    }

    static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data? = autoreleasepool { try? h.read(upToCount: 8 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Async(_ url: URL) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: sha256(url)) }
        }
    }
}

// MARK: - Formatierung

enum Fmt {
    static func bytes(_ b: Int64?) -> String {
        guard let b else { return "–" }
        if b <= 0 { return "0 KB" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: b)
    }

    static func gbShort(_ b: Int64) -> String {
        "\(Int((Double(b) / 1e9).rounded())) GB"
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "–" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        return f.string(from: d)
    }

    static func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Sicherheitsnetz

enum Safety {
    /// Diese Ordner selbst werden nie gelöscht (nur Inhalte darin)
    static let protectedRel: Set<String> = [
        "", "/Library", "/Library/Caches", "/Library/Application Support", "/Library/Containers",
        "/Library/Group Containers", "/Library/Preferences", "/Library/Keychains", "/Library/Mail",
        "/Library/Thunderbird", "/Library/Logs", "/Documents", "/Desktop", "/Downloads", "/Movies",
        "/Pictures", "/Music", "/Sites", "/Sites/localhost", "/.ssh", "/.config", "/.cache", "/.npm",
        "/Applications", "/Library/CloudStorage", "/Library/Mobile Documents"
    ]

    static func isAllowed(_ url: URL, extraProtected: [String]) -> Bool {
        let p = url.standardizedFileURL.path
        let home = Paths.home
        guard p.hasPrefix(home + "/") else { return false }
        if extraProtected.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == p }) { return false }
        let rel = String(p.dropFirst(home.count))
        if protectedRel.contains(rel) { return false }
        if rel.hasPrefix("/.ssh") || rel.hasPrefix("/Library/Keychains") { return false }
        return true
    }
}

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

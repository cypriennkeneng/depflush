import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @ObservedObject var disk = DiskMonitor.shared
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: disk.isLow ? "exclamationmark.triangle.fill" : "internaldrive")
            Text(Fmt.gbShort(disk.free))
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var disk: DiskMonitor
    @EnvironmentObject var model: CleanerModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("language") private var language = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AppBadge(size: 26)
                Text(AppInfo.name).font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: disk.usedFraction)
                    .tint(disk.isLow ? .red : .accentColor)
                HStack {
                    Text(L("%@ frei", Fmt.bytes(disk.free))).fontWeight(.medium)
                    Spacer()
                    Text(L("von %@", Fmt.bytes(disk.total))).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if disk.isLow {
                Label(L("Weniger als %d GB frei – Zeit zum Aufräumen", disk.thresholdGB), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let last = model.history.first {
                Text(L("Zuletzt aufgeräumt %@: %@", Fmt.relative(last.date), Fmt.bytes(last.estimated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let support = AppInfo.supportURL, !model.history.isEmpty {
                Link(destination: support) {
                    Label(L("Hat geholfen? Spendier uns einen Kaffee"), systemImage: "cup.and.saucer")
                }
                .font(.caption)
            }
            Divider()
            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(L("Öffnen"), systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(L("Beenden"), systemImage: "power")
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .id(language)
        .onAppear { disk.refresh() }
    }
}

struct AppBadge: View {
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.70), Color(red: 0.10, green: 0.40, blue: 0.85)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "sparkles").font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.white))
    }
}

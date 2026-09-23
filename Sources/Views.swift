import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Grundgerüst

struct ContentView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var disk: DiskMonitor
    @State private var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                DiskCard()
                    .padding(.vertical, 6)
                Section {
                    ForEach([Pane.overview, .caches, .dev, .docker]) { p in
                        Label(p.title, systemImage: p.icon)
                            .badge(badge(p))
                            .tag(p)
                    }
                }
                Section {
                    ForEach([Pane.history, .settings]) { p in
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch pane ?? .overview {
            case .overview: OverviewView(pane: $pane)
            case .caches:
                CleanPaneView(pane: .caches,
                              subtitle: "Zwischenspeicher, die sich von selbst neu aufbauen. Ist eine App geöffnet, wird ihr Cache übersprungen.")
            case .dev:
                CleanPaneView(pane: .dev,
                              subtitle: "vendor/node_modules (mit composer.lock bzw. package.json – jederzeit wiederherstellbar) und SQL-Dumps in \(model.projectRoot).")
            case .docker: DockerView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .alert("Bereinigung abgeschlossen",
               isPresented: Binding(get: { model.resultMessage != nil }, set: { if !$0 { model.resultMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.resultMessage ?? "")
        }
        .task {
            if model.lastScan.isEmpty { await model.scanAll() }
        }
    }

    private func badge(_ p: Pane) -> Text? {
        let s = model.selectedSize(p)
        return s > 0 ? Text(Fmt.gbShort(s)) : nil
    }
}

struct DiskCard: View {
    @EnvironmentObject var disk: DiskMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppBadge(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aufräumer").font(.headline)
                    Text("Macintosh HD").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: disk.usedFraction)
                .tint(disk.isLow ? .red : .accentColor)
            Text("\(Fmt.bytes(disk.free)) frei von \(Fmt.bytes(disk.total))")
                .font(.caption)
                .foregroundStyle(disk.isLow ? .red : .secondary)
        }
    }
}

struct PaneHeader: View {
    let pane: Pane
    let subtitle: String
    @EnvironmentObject var model: CleanerModel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.title).font(.largeTitle.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    Task { await model.scan(pane) }
                } label: {
                    if model.busy.contains(pane) {
                        ProgressView().controlSize(.small).frame(width: 60)
                    } else {
                        Label("Neu scannen", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.busy.contains(pane))
                if let d = model.lastScan[pane] {
                    Text("Gescannt \(Fmt.relative(d))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Übersicht

struct OverviewView: View {
    @Binding var pane: Pane?
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var disk: DiskMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(pane: .overview, subtitle: "Wo dein Speicher steckt und was sich aufräumen lässt.")

                HStack(spacing: 14) {
                    StatTile(title: "Frei", value: Fmt.bytes(disk.free), icon: "checkmark.circle", tint: disk.isLow ? .red : .green)
                    StatTile(title: "Belegt", value: Fmt.bytes(max(0, disk.total - disk.free)), icon: "internaldrive", tint: .blue)
                    StatTile(title: "Zum Aufräumen vorgemerkt", value: Fmt.bytes(model.totalSelected), icon: "sparkles", tint: .orange)
                }

                if let swap = model.swap, swap > 2_000_000_000 {
                    Callout(icon: "arrow.triangle.2.circlepath",
                            text: "Die Auslagerungsdatei (Swap) belegt \(Fmt.bytes(swap)). Ein Neustart des Macs gibt diesen Platz frei.")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Größte Bereiche").font(.headline)
                    if model.overview.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text(model.busy.contains(.overview) ? "Analysiere …" : "Noch nicht gescannt").foregroundStyle(.secondary) }
                            .padding(.vertical, 20)
                    } else {
                        let maxSize = model.overview.compactMap(\.size).max() ?? 1
                        ForEach(model.overview) { row in
                            UsageRowView(row: row, maxSize: maxSize) { p in pane = p }
                            if row.id != model.overview.last?.id { Divider() }
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
            }
            .padding(24)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(tint)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Callout: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.blue)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct UsageRowView: View {
    let row: UsageRow
    let maxSize: Int64
    let go: (Pane) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).fontWeight(.medium)
                if let p = row.path {
                    Text(Paths.tilde(p)).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(Fmt.bytes(row.size)).monospacedDigit().fontWeight(.medium)
                if let p = row.path {
                    Button { revealInFinder(p) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless).help("Im Finder zeigen")
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(4, geo.size.width * CGFloat(Double(row.size ?? 0) / Double(max(maxSize, 1)))))
                }
            }
            .frame(height: 6)
            if row.hint != nil || row.pane != nil {
                HStack(spacing: 8) {
                    if let h = row.hint { Text(h).font(.caption).foregroundStyle(.secondary) }
                    if let p = row.pane {
                        Button("Zu „\(p.title)“ →") { go(p) }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Aufräum-Listen

struct CleanPaneView: View {
    let pane: Pane
    let subtitle: String
    var extra: AnyView? = nil
    @EnvironmentObject var model: CleanerModel
    @State private var confirm = false

    private var items: [CleanItem] { model.items(for: pane) }
    private var groups: [String] {
        var seen: [String] = []
        for i in items where !seen.contains(i.group) { seen.append(i.group) }
        return seen
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PaneHeader(pane: pane, subtitle: subtitle)
                if let extra { extra }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            if items.isEmpty {
                Spacer()
                if model.busy.contains(pane) || model.lastScan[pane] == nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(model.status.isEmpty ? "Scanne …" : model.status).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("Alles sauber", systemImage: "checkmark.seal",
                                           description: Text("Hier gibt es gerade nichts aufzuräumen."))
                }
                Spacer()
            } else {
                List {
                    ForEach(groups, id: \.self) { g in
                        Section {
                            ForEach(items.filter { $0.group == g }) { item in
                                ItemRow(item: item, pane: pane)
                            }
                        } header: {
                            HStack {
                                Text(g)
                                Spacer()
                                Button("Alle") { model.setAll(true, in: pane, group: g) }
                                Button("Keine") { model.setAll(false, in: pane, group: g) }
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            FooterBar(pane: pane, confirm: $confirm)
        }
        .task(id: pane) {
            if model.lastScan[pane] == nil { await model.scan(pane) }
        }
        .alert("\(Fmt.bytes(model.selectedSize(pane))) endgültig löschen?", isPresented: $confirm) {
            Button("Löschen", role: .destructive) { Task { await model.clean(pane) } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(model.selectedSummary(pane))
        }
    }
}

struct ItemRow: View {
    let item: CleanItem
    let pane: Pane
    @EnvironmentObject var model: CleanerModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { item.selected }, set: { model.toggle(item.id, in: pane, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.blockedBy != nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let b = item.blockedBy {
                    Label("\(b) ist geöffnet – App beenden und neu scannen", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let w = item.warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(item.isActive ? .primary : .secondary)
            if let p = item.revealPath {
                Button { revealInFinder(p) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Im Finder zeigen")
            }
        }
        .padding(.vertical, 4)
        .opacity(item.blockedBy != nil ? 0.6 : 1)
    }
}

struct FooterBar: View {
    let pane: Pane
    @Binding var confirm: Bool
    @EnvironmentObject var model: CleanerModel

    var body: some View {
        HStack(spacing: 10) {
            if model.busy.contains(pane) {
                ProgressView().controlSize(.small)
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                Text("\(model.selectedCount(pane)) ausgewählt · \(Fmt.bytes(model.selectedSize(pane)))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                confirm = true
            } label: {
                Label("Bereinigen …", systemImage: "trash")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.selectedCount(pane) == 0 || model.busy.contains(pane))
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Docker

struct DockerView: View {
    @EnvironmentObject var model: CleanerModel

    var body: some View {
        switch model.dockerState {
        case .notInstalled:
            ContentUnavailableView("Docker ist nicht installiert", systemImage: "shippingbox")
        case .stopped, .starting:
            ContentUnavailableView {
                Label(model.dockerState == .starting ? "Docker startet …" : "Docker läuft nicht", systemImage: "shippingbox")
            } description: {
                Text("Damit ich Images, Container und Volumes prüfen kann, muss Docker Desktop laufen.")
            } actions: {
                if model.dockerState == .starting {
                    ProgressView()
                } else {
                    Button("Docker starten") { model.startDocker() }.buttonStyle(.borderedProminent)
                    Button("Erneut prüfen") { Task { await model.scan(.docker) } }
                }
            }
        case .unknown, .running:
            CleanPaneView(pane: .docker,
                          subtitle: "Ungenutzte Images und Build-Cache sind vorausgewählt. Container und Volumes nur, wenn du sie bewusst anhakst.",
                          extra: AnyView(DockerSummary()))
        }
    }
}

struct DockerSummary: View {
    @EnvironmentObject var model: CleanerModel
    var body: some View {
        if !model.dockerSummary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let raw = model.dockerRaw {
                    Text("Docker-Datei auf der Platte: \(Fmt.bytes(raw))").fontWeight(.medium)
                }
                ForEach(model.dockerSummary, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Verlauf

struct HistoryView: View {
    @EnvironmentObject var model: CleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verlauf").font(.largeTitle.weight(.semibold))
                Text("Insgesamt freigegeben: \(Fmt.bytes(model.history.reduce(0) { $0 + $1.estimated }))")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            if model.history.isEmpty {
                ContentUnavailableView("Noch nichts aufgeräumt", systemImage: "clock.arrow.circlepath")
            } else {
                List(model.history) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(e.area).fontWeight(.medium)
                            Text(Fmt.dateTime(e.date)).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.bytes(e.estimated)).monospacedDigit().fontWeight(.medium)
                        }
                        Text(e.items.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @AppStorage("projectRoot") private var projectRoot = "~/Sites"
    @AppStorage("inactiveMonths") private var inactiveMonths = 12
    @AppStorage("warnGB") private var warnGB = 20
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var disk: DiskMonitor

    var body: some View {
        Form {
            Section("Entwicklung") {
                LabeledContent("Projektordner") {
                    HStack {
                        Text(projectRoot).foregroundStyle(.secondary)
                        Button("Ändern …") { chooseRoot() }
                    }
                }
                Stepper("Projekte gelten als ruhend nach \(inactiveMonths) Monaten", value: $inactiveMonths, in: 1...48)
            }
            Section("Menüleiste & Warnung") {
                Stepper("Warnen, wenn weniger als \(warnGB) GB frei sind", value: $warnGB, in: 5...200, step: 5)
                    .onChange(of: warnGB) { disk.refresh() }
                Toggle("Beim Anmelden automatisch starten", isOn: $loginItem)
                    .onChange(of: loginItem) { setLogin(loginItem) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Berechtigungen") {
                Text("Für vollständige Größenangaben (z. B. Mail, iPhone-Backups) braucht der Aufräumer den Festplattenvollzugriff. Gelöscht wird nie etwas ohne deine Bestätigung.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Festplattenvollzugriff öffnen …") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
                }
            }
            Section("Über") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Verlauf", value: "~/Library/Application Support/Aufraeumer")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
    }

    private func chooseRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: Paths.expand(projectRoot))
        if p.runModal() == .OK, let u = p.url {
            projectRoot = Paths.tilde(u.path)
            model.lastScan[.dev] = nil
            model.dev = []
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Konnte nicht geändert werden: \(error.localizedDescription)"
        }
        loginItem = SMAppService.mainApp.status == .enabled
    }
}

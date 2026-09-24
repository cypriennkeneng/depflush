import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Grundgerüst

struct ContentView: View {
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var disk: DiskMonitor
    @State private var pane: Pane? = .overview
    @AppStorage("language") private var language = "system"
    @AppStorage("welcomeShown") private var welcomeShown = false

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
                              subtitle: L("Zwischenspeicher, die sich von selbst neu aufbauen. Ist eine App geöffnet, wird ihr Cache übersprungen."))
            case .dev:
                if model.projectRoots.isEmpty {
                    ContentUnavailableView {
                        Label(L("Kein Projektordner"), systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(L("Füge in den Einstellungen die Ordner hinzu, in denen deine Projekte liegen."))
                    } actions: {
                        Button(L("Zu den Einstellungen")) { pane = .settings }
                    }
                } else {
                    CleanPaneView(pane: .dev,
                                  subtitle: L("vendor/node_modules (nur mit composer.lock bzw. package.json – jederzeit wiederherstellbar) und SQL-Dumps in: %@", model.projectRoots.joined(separator: ", ")))
                }
            case .docker: DockerView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .id(language)
        .alert(L("Bereinigung abgeschlossen"),
               isPresented: Binding(get: { model.resultMessage != nil }, set: { if !$0 { model.resultMessage = nil } })) {
            if model.offerEmptyTrash {
                Button(L("Papierkorb jetzt leeren"), role: .destructive) { Task { await model.emptyTrash() } }
                Button(L("Später"), role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: {
            Text(model.resultMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { !welcomeShown }, set: { if !$0 { welcomeShown = true } })) {
            WelcomeView { welcomeShown = true }
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

struct WelcomeView: View {
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppBadge(size: 48)
                VStack(alignment: .leading) {
                    Text(L("Willkommen bei %@", AppInfo.name)).font(.title2.weight(.semibold))
                    Text(L("Platz schaffen auf dem Mac – sicher und nachvollziehbar.")).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(L("Nichts wird ohne deine Bestätigung gelöscht. Du siehst vorher jede Datei mit Größe."), systemImage: "checkmark.shield")
                Label(L("Standardmäßig landet alles im Papierkorb – umstellbar in den Einstellungen."), systemImage: "trash")
                Label(L("Alles bleibt auf deinem Mac. Die App sendet keine Daten."), systemImage: "lock")
                Label(L("Für vollständige Werte kannst du in den Einstellungen den Festplattenvollzugriff erteilen."), systemImage: "externaldrive.badge.checkmark")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Los geht's")) { done() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

struct DiskCard: View {
    @EnvironmentObject var disk: DiskMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppBadge(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(AppInfo.name).font(.headline)
                    Text("Macintosh HD").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: disk.usedFraction)
                .tint(disk.isLow ? .red : .accentColor)
            Text(L("%@ frei von %@", Fmt.bytes(disk.free), Fmt.bytes(disk.total)))
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
                        Label(L("Neu scannen"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.busy.contains(pane))
                if let d = model.lastScan[pane] {
                    Text(L("Gescannt %@", Fmt.relative(d))).font(.caption).foregroundStyle(.secondary)
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
                PaneHeader(pane: .overview, subtitle: L("Wo dein Speicher steckt und was sich aufräumen lässt."))

                HStack(spacing: 14) {
                    StatTile(title: L("Frei"), value: Fmt.bytes(disk.free), icon: "checkmark.circle", tint: disk.isLow ? .red : .green)
                    StatTile(title: L("Belegt"), value: Fmt.bytes(max(0, disk.total - disk.free)), icon: "internaldrive", tint: .blue)
                    StatTile(title: L("Zum Aufräumen vorgemerkt"), value: Fmt.bytes(model.totalSelected), icon: "sparkles", tint: .orange)
                }

                if let swap = model.swap, swap > 2_000_000_000 {
                    Callout(icon: "arrow.triangle.2.circlepath",
                            text: L("Die Auslagerungsdatei (Swap) belegt %@. Ein Neustart des Macs gibt diesen Platz frei.", Fmt.bytes(swap)))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Größte Bereiche")).font(.headline)
                    if model.overview.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.busy.contains(.overview) ? L("Analysiere …") : L("Noch nicht gescannt")).foregroundStyle(.secondary)
                        }
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
                        .buttonStyle(.borderless).help(L("Im Finder zeigen"))
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
                        Button(L("Zu „%@“ →", p.title)) { go(p) }.buttonStyle(.link).font(.caption)
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
    private var confirmTitle: String {
        let size = Fmt.bytes(model.selectedSize(pane))
        let files = model.items(for: pane).filter(\.isActive).contains { $0.action.isFileDelete }
        return (model.useTrash && files) ? L("%@ in den Papierkorb legen?", size) : L("%@ endgültig löschen?", size)
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
                        Text(model.status.isEmpty ? L("Scanne …") : model.status).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(L("Alles sauber"), systemImage: "checkmark.seal",
                                           description: Text(L("Hier gibt es gerade nichts aufzuräumen.")))
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
                                Button(L("Alle")) { model.setAll(true, in: pane, group: g) }
                                Button(L("Keine")) { model.setAll(false, in: pane, group: g) }
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
        .alert(confirmTitle, isPresented: $confirm) {
            Button(model.useTrash ? L("Entfernen") : L("Löschen"), role: .destructive) { Task { await model.clean(pane) } }
            Button(L("Abbrechen"), role: .cancel) {}
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
                    Label(L("%@ ist geöffnet – App beenden und neu scannen", b), systemImage: "lock.fill")
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
                    .buttonStyle(.borderless).help(L("Im Finder zeigen"))
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
                Text(L("%d ausgewählt · %@", model.selectedCount(pane), Fmt.bytes(model.selectedSize(pane))))
                    .foregroundStyle(.secondary)
                if model.useTrash {
                    Label(L("Papierkorb-Modus"), systemImage: "trash").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                confirm = true
            } label: {
                Label(L("Bereinigen …"), systemImage: "trash")
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
            ContentUnavailableView(L("Docker ist nicht installiert"), systemImage: "shippingbox")
        case .stopped, .starting:
            ContentUnavailableView {
                Label(model.dockerState == .starting ? L("Docker startet …") : L("Docker läuft nicht"), systemImage: "shippingbox")
            } description: {
                Text(L("Damit Images, Container und Volumes geprüft werden können, muss Docker laufen."))
            } actions: {
                if model.dockerState == .starting {
                    ProgressView()
                } else {
                    Button(L("Docker starten")) { model.startDocker() }.buttonStyle(.borderedProminent)
                    Button(L("Erneut prüfen")) { Task { await model.scan(.docker) } }
                }
            }
        case .unknown, .running:
            CleanPaneView(pane: .docker,
                          subtitle: L("Ungenutzte Images und Build-Cache sind vorausgewählt. Container und Volumes nur, wenn du sie bewusst anhakst."),
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
                    Text(L("Docker-Datei auf der Platte: %@", Fmt.bytes(raw))).fontWeight(.medium)
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
                Text(L("Verlauf")).font(.largeTitle.weight(.semibold))
                Text(L("Insgesamt aufgeräumt: %@", Fmt.bytes(model.history.reduce(0) { $0 + $1.estimated })))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            if model.history.isEmpty {
                ContentUnavailableView(L("Noch nichts aufgeräumt"), systemImage: "clock.arrow.circlepath")
            } else {
                List(model.history) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(e.area).fontWeight(.medium)
                            Text(Fmt.dateTime(e.date)).foregroundStyle(.secondary)
                            if e.toTrash == true {
                                Label(L("Papierkorb"), systemImage: "trash").font(.caption).foregroundStyle(.secondary)
                            }
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
    @AppStorage("inactiveMonths") private var inactiveMonths = 12
    @AppStorage("warnGB") private var warnGB = 20
    @AppStorage("useTrash") private var useTrash = true
    @AppStorage("language") private var language = "system"
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @EnvironmentObject var model: CleanerModel
    @EnvironmentObject var disk: DiskMonitor

    var body: some View {
        Form {
            Section(L("Allgemein")) {
                Picker(L("Sprache"), selection: $language) {
                    Text(L("Systemsprache")).tag("system")
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                }
                .onChange(of: language) { model.languageChanged() }
                Picker(L("Beim Bereinigen"), selection: $useTrash) {
                    Text(L("In den Papierkorb legen (umkehrbar)")).tag(true)
                    Text(L("Endgültig löschen (Platz sofort frei)")).tag(false)
                }
                .onChange(of: useTrash) { model.objectWillChange.send() }
            }
            Section(L("Projektordner")) {
                if model.projectRoots.isEmpty {
                    Text(L("Noch kein Ordner – füge den Ordner hinzu, in dem deine Projekte liegen.")).foregroundStyle(.secondary)
                }
                ForEach(model.projectRoots, id: \.self) { r in
                    HStack {
                        Image(systemName: "folder")
                        Text(r)
                        Spacer()
                        Button { model.projectRoots.removeAll { $0 == r } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L("Entfernen"))
                    }
                }
                HStack {
                    Button(L("Ordner hinzufügen …")) { addRoot() }
                    Button(L("Automatisch erkennen")) {
                        let found = ProjectRoots.detect().filter { !model.projectRoots.contains($0) }
                        if !found.isEmpty { model.projectRoots += found }
                    }
                }
                Stepper(L("Projekte gelten als ruhend nach %d Monaten", inactiveMonths), value: $inactiveMonths, in: 1...48)
            }
            Section(L("Menüleiste & Warnung")) {
                Stepper(L("Warnen, wenn weniger als %d GB frei sind", warnGB), value: $warnGB, in: 5...200, step: 5)
                    .onChange(of: warnGB) { disk.refresh() }
                Toggle(L("Beim Anmelden automatisch starten"), isOn: $loginItem)
                    .onChange(of: loginItem) { setLogin(loginItem) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section(L("Berechtigungen")) {
                Text(L("Für vollständige Größenangaben (z. B. Mail, iPhone-Backups) braucht die App den Festplattenvollzugriff. Gelöscht wird nie etwas ohne deine Bestätigung."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L("Festplattenvollzugriff öffnen …")) {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
                }
            }
            Section(L("Über")) {
                LabeledContent(L("Version"), value: AppInfo.version)
                LabeledContent(L("Verlauf"), value: "~/Library/Application Support/Depflush")
                if let support = AppInfo.supportURL {
                    Link(destination: support) {
                        Label(L("Depflush unterstützen – spendier uns einen Kaffee"), systemImage: "cup.and.saucer")
                    }
                }
                Link(destination: URL(string: "https://depflush.com")!) { Label("depflush.com", systemImage: "globe") }
                Link(destination: URL(string: "https://github.com/webloupe/depflush")!) {
                    Label(L("Quellcode auf GitHub (GPL-3.0)"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://webloupe.de")!) {
                    Label(L("Entwickelt von Webloupe – Shopware-Entwicklung & Updates"), systemImage: "hammer")
                }
                Button(L("Willkommensbildschirm erneut zeigen")) { UserDefaults.standard.set(false, forKey: "welcomeShown") }
            }
        }
        .formStyle(.grouped)
    }

    private func addRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: Paths.home)
        if p.runModal() == .OK {
            let new = p.urls.map { Paths.tilde($0.path) }.filter { !model.projectRoots.contains($0) }
            model.projectRoots += new
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = L("Konnte nicht geändert werden: %@", error.localizedDescription)
        }
        loginItem = SMAppService.mainApp.status == .enabled
    }
}

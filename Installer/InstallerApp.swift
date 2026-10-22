// Softswirl Web-Apps – Installer (SwiftUI, macOS 13+).
// Web-Apps: mitgelieferte, notarisierte WebKit-Apps nach ~/Applications kopieren (Quarantaene-Flag entfernen) und ins Dock legen.
// Programme: TeamViewer QuickSupport (DMG laden, Signatur pruefen, nach /Applications) und Bitdefender (Central-Link oeffnen,
// auf das heruntergeladene Paket warten, Signatur pruefen, mit Admin-Rechten installieren).
// Bauen: scripts/build_release.sh (swiftc -parse-as-library).
import SwiftUI
import AppKit

struct Entry: Identifiable, Decodable, Hashable {
    let name: String
    let slug: String
    let kind: String?          // webapp (Standard) | dmgapp | pkgwatch
    let url: String?
    let description: String?
    let teamId: String?        // dmgapp: erwartete TeamIdentifier der App im DMG
    let appName: String?       // dmgapp: Name der .app im DMG
    let signer: String?        // pkgwatch: erwarteter Text in `pkgutil --check-signature`
    let pkgMatch: String?      // pkgwatch: Teil des Dateinamens (klein geschrieben)
    var id: String { slug }
    var kindValue: String { kind ?? "webapp" }
    var isWebApp: Bool { kindValue == "webapp" }
}

enum Shell {
    @discardableResult
    static func run(_ cmd: String, _ args: [String], timeout: Double = 600) -> (code: Int32, out: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: cmd); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error.localizedDescription)") }
        var data = Data(); let g = DispatchGroup(); g.enter()
        DispatchQueue.global().async { data = pipe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if g.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return (-2, "Zeitlimit") }
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    /// Befehl mit Admin-Rechten (macOS-Passwortdialog) ueber AppleScript.
    static func privileged(_ command: String) -> (code: Int32, out: String) {
        let esc = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(esc)\" with administrator privileges"])
    }
    static func removeQuarantine(_ path: String) { run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", path]) }
}

@MainActor
final class InstallerModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var install: Set<String> = []
    @Published var dock: Set<String> = []
    @Published var links: [String: String] = [:]
    @Published var chosenPackages: [String: URL] = [:]
    @Published var busy = false
    @Published var finished = false
    @Published var status = ""
    @Published var log: [String] = []

    let appsDir: URL = Bundle.main.resourceURL!.appendingPathComponent("Apps", isDirectory: true)
    let userApps: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    let logo: NSImage? = Bundle.main.url(forResource: "logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var webApps: [Entry] { entries.filter { $0.isWebApp } }
    var programs: [Entry] { entries.filter { !$0.isWebApp } }

    init() {
        if let u = Bundle.main.url(forResource: "apps", withExtension: "json"), let d = try? Data(contentsOf: u),
           let list = try? JSONDecoder().decode([Entry].self, from: d) {
            entries = list.filter { !$0.isWebApp || FileManager.default.fileExists(atPath: bundledApp($0).path) }
        }
        install = Set(webApps.map { $0.slug }); dock = install
    }
    func bundledApp(_ e: Entry) -> URL { appsDir.appendingPathComponent("\(e.name).app") }
    func installedPath(_ e: Entry) -> URL {
        switch e.kindValue {
        case "dmgapp": return URL(fileURLWithPath: "/Applications").appendingPathComponent(e.appName ?? "\(e.name).app")
        case "pkgwatch": return URL(fileURLWithPath: "/Applications/\(e.name)")
        default: return userApps.appendingPathComponent("\(e.name).app")
        }
    }
    func isInstalled(_ e: Entry) -> Bool { FileManager.default.fileExists(atPath: installedPath(e).path) }
    func icon(_ e: Entry) -> NSImage {
        if e.isWebApp { return NSWorkspace.shared.icon(forFile: bundledApp(e).path) }
        if isInstalled(e) { return NSWorkspace.shared.icon(forFile: installedPath(e).path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
    func selectAll(_ on: Bool) { install = on ? Set(entries.map { $0.slug }) : []; dock = on ? Set(entries.filter { $0.kindValue != "pkgwatch" }.map { $0.slug }) : [] }
    func choosePackage(for e: Entry) {
        let p = NSOpenPanel(); p.allowedContentTypes = [.package, .data]; p.allowsMultipleSelection = false; p.message = "Bitdefender-Installationspaket (.pkg) wählen"
        if p.runModal() == .OK, let u = p.url { chosenPackages[e.slug] = u; install.insert(e.slug) }
    }

    func run() {
        guard !busy else { return }
        busy = true; finished = false; log = []; status = "Installiere …"
        let todo = entries.filter { install.contains($0.slug) }
        let dockSet = dock, links = links, packages = chosenPackages
        let appsDir = appsDir, userApps = userApps
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lines: [String] = []; var dockPaths: [String] = []
            func say(_ s: String) { lines.append(s); let snap = lines; DispatchQueue.main.async { self?.log = snap; self?.status = s } }
            let fm = FileManager.default
            try? fm.createDirectory(at: userApps, withIntermediateDirectories: true)
            for e in todo {
                switch e.kindValue {
                case "webapp":
                    let src = appsDir.appendingPathComponent("\(e.name).app"), dst = userApps.appendingPathComponent("\(e.name).app")
                    do {
                        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                        try fm.copyItem(at: src, to: dst)
                        Shell.removeQuarantine(dst.path)          // notarisiert und bereits beim Installer geprueft: kein Erstöffnen-Dialog je App
                        say("✓ \(e.name) installiert")
                        if dockSet.contains(e.slug) { dockPaths.append(dst.path) }
                    } catch { say("✗ \(e.name): \(error.localizedDescription)") }
                case "dmgapp":
                    guard let urlS = e.url, let url = URL(string: urlS), let appName = e.appName else { say("✗ \(e.name): Eintrag unvollständig"); continue }
                    say("⇣ \(e.name) wird geladen …")
                    let tmp = fm.temporaryDirectory.appendingPathComponent("\(e.slug)-\(UUID().uuidString).dmg")
                    let sem = DispatchSemaphore(value: 0); var dlError: String? = nil
                    URLSession.shared.downloadTask(with: url) { loc, _, err in
                        if let loc = loc { try? fm.moveItem(at: loc, to: tmp) } else { dlError = err?.localizedDescription ?? "Download fehlgeschlagen" }
                        sem.signal()
                    }.resume()
                    sem.wait()
                    if let dlError = dlError { say("✗ \(e.name): \(dlError)"); continue }
                    let att = Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", tmp.path])
                    guard let mount = att.out.split(separator: "\n").last?.split(separator: "\t").last.map({ String($0).trimmingCharacters(in: .whitespaces) }), att.code == 0 else { say("✗ \(e.name): DMG lässt sich nicht öffnen"); continue }
                    let appInDmg = (mount as NSString).appendingPathComponent(appName)
                    let sig = Shell.run("/usr/bin/codesign", ["-dvv", appInDmg]).out
                    let ok = (e.teamId == nil || sig.contains("TeamIdentifier=\(e.teamId!)")) && Shell.run("/usr/sbin/spctl", ["-a", "-t", "exec", appInDmg]).code == 0
                    if ok {
                        let dst = "/Applications/\(appName)"
                        var r: (code: Int32, out: String)
                        if fm.isWritableFile(atPath: "/Applications") {
                            r = Shell.run("/bin/rm", ["-rf", dst]); r = Shell.run("/usr/bin/ditto", [appInDmg, dst])
                        } else {
                            r = Shell.privileged("rm -rf '\(dst)' && ditto '\(appInDmg)' '\(dst)'")
                        }
                        if r.code == 0 { Shell.removeQuarantine(dst); say("✓ \(e.name) installiert (/Applications)"); if dockSet.contains(e.slug) { dockPaths.append(dst) } }
                        else { say("✗ \(e.name): Kopieren fehlgeschlagen (\(r.out.trimmingCharacters(in: .whitespacesAndNewlines)))") }
                    } else { say("✗ \(e.name): Signatur nicht bestätigt – nicht installiert") }
                    Shell.run("/usr/bin/hdiutil", ["detach", mount, "-quiet"]); try? fm.removeItem(at: tmp)
                case "pkgwatch":
                    var pkg: URL? = packages[e.slug]
                    if pkg == nil {
                        guard let link = links[e.slug]?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty, let u = URL(string: link) else { say("✗ \(e.name): kein Link und kein Paket gewählt"); continue }
                        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                        let before = Set((try? fm.contentsOfDirectory(atPath: downloads.path)) ?? [])
                        DispatchQueue.main.async { NSWorkspace.shared.open(u) }
                        say("⌛ \(e.name): Seite geöffnet – bitte dort auf Herunterladen klicken. Warte auf das Paket in \u{201E}Downloads\u{201C} …")
                        let match = (e.pkgMatch ?? e.name).lowercased()
                        for _ in 0..<180 {
                            Thread.sleep(forTimeInterval: 5)
                            let now = (try? fm.contentsOfDirectory(atPath: downloads.path)) ?? []
                            if now.contains(where: { $0.hasSuffix(".download") }) { continue }
                            if let f = now.first(where: { !before.contains($0) && $0.lowercased().contains(match) && $0.lowercased().hasSuffix(".pkg") }) { pkg = downloads.appendingPathComponent(f); break }
                        }
                        if pkg == nil { say("✗ \(e.name): kein Paket innerhalb von 15 Minuten erschienen"); continue }
                        Thread.sleep(forTimeInterval: 3)
                    }
                    let check = Shell.run("/usr/sbin/pkgutil", ["--check-signature", pkg!.path]).out
                    guard check.contains(e.signer ?? "Developer ID Installer") else { say("✗ \(e.name): Paketsignatur nicht bestätigt – nicht installiert"); continue }
                    say("⚙︎ \(e.name) wird installiert (Admin-Passwort) …")
                    let r = Shell.privileged("/usr/sbin/installer -pkg '\(pkg!.path)' -target /")
                    if r.code == 0 { say("✓ \(e.name) installiert – Freigaben in den Systemeinstellungen (Erweiterungen, Festplattenzugriff) noch bestätigen") }
                    else { say("✗ \(e.name): \(r.out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(160))") }
                default: say("✗ \(e.name): unbekannter Typ")
                }
            }
            if !dockPaths.isEmpty { InstallerModel.addToDock(paths: dockPaths); say("✓ \(dockPaths.count) Einträge im Dock") }
            let result = lines
            DispatchQueue.main.async {
                self?.log = result; self?.busy = false; self?.finished = true
                self?.status = result.contains { $0.hasPrefix("✗") } ? "Fertig, mit Hinweisen" : "Fertig"
            }
        }
    }

    nonisolated static func addToDock(paths: [String]) {
        let domain = "com.apple.dock" as CFString
        var apps = (CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]]) ?? []
        func urlString(_ p: String) -> String { URL(fileURLWithPath: p, isDirectory: true).absoluteString }
        let wanted = paths.map { urlString($0) }
        apps.removeAll { entry in
            guard let td = entry["tile-data"] as? [String: Any], let fd = td["file-data"] as? [String: Any], let s = fd["_CFURLString"] as? String else { return false }
            return wanted.contains(s) || wanted.contains(s + "/")
        }
        for p in paths { apps.append(["tile-data": ["file-data": ["_CFURLString": urlString(p), "_CFURLStringType": 15]], "tile-type": "file-tile"]) }
        CFPreferencesSetAppValue("persistent-apps" as CFString, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        Shell.run("/usr/bin/killall", ["Dock"])
    }
}

struct EntryRow: View {
    @ObservedObject var model: InstallerModel
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(nsImage: model.icon(entry)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(entry.name).font(.headline)
                        if model.isInstalled(entry) { Text("installiert").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
                    }
                    Text(entry.description ?? entry.url ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Toggle("Installieren", isOn: Binding(
                    get: { model.install.contains(entry.slug) },
                    set: { on in if on { model.install.insert(entry.slug) } else { model.install.remove(entry.slug); model.dock.remove(entry.slug) } }))
                if entry.kindValue != "pkgwatch" {
                    Toggle("Ins Dock", isOn: Binding(
                        get: { model.dock.contains(entry.slug) },
                        set: { on in if on { model.dock.insert(entry.slug); model.install.insert(entry.slug) } else { model.dock.remove(entry.slug) } }))
                        .disabled(!model.install.contains(entry.slug))
                }
            }
            if entry.kindValue == "pkgwatch" {
                HStack(spacing: 8) {
                    TextField("Download-Link aus Bitdefender Central einfügen", text: Binding(get: { model.links[entry.slug] ?? "" }, set: { model.links[entry.slug] = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Paket wählen …") { model.choosePackage(for: entry) }
                    if let p = model.chosenPackages[entry.slug] { Text(p.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .padding(.leading, 58)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
    }
}

struct ContentView: View {
    @StateObject var model = InstallerModel()
    let accent = Color(red: 0.66, green: 0.61, blue: 0.94)
    let gradient = LinearGradient(colors: [Color(red: 0.96, green: 0.65, blue: 0.78), Color(red: 0.66, green: 0.61, blue: 0.94)], startPoint: .bottomLeading, endPoint: .topTrailing)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if let logo = model.logo { Image(nsImage: logo).resizable().interpolation(.high).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Softswirl Studio").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).textCase(.uppercase)
                    Text("Apps installieren").font(.title.weight(.bold)).foregroundStyle(.white)
                    Text("Web-Apps mit eigenem Fenster und eigener Anmeldung, dazu die Programme fürs Gerät.").font(.callout).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(24)
            .background(Color(red: 0.086, green: 0.098, blue: 0.106))
            .overlay(alignment: .bottom) { Rectangle().fill(gradient).frame(height: 3) }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.webApps.isEmpty { Text("Web-Apps").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4) }
                    ForEach(model.webApps) { EntryRow(model: model, entry: $0) }
                    if !model.programs.isEmpty { Text("Programme").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 10) }
                    ForEach(model.programs) { EntryRow(model: model, entry: $0) }
                    if model.entries.isEmpty { Text("Keine Einträge gefunden.").foregroundStyle(.secondary).padding() }
                }
                .padding(20)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Alle") { model.selectAll(true) }
                Button("Keine") { model.selectAll(false) }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if model.finished {
                    Button("Beenden") { NSApp.terminate(nil) }
                } else {
                    Button("Installieren") { model.run() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.busy || model.install.isEmpty)
                }
            }
            .padding(16)
            if !model.log.isEmpty {
                VStack(alignment: .leading, spacing: 4) { ForEach(model.log, id: \.self) { Text($0).font(.caption.monospaced()) } }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 600, idealHeight: 720)
        .tint(accent)
    }
}

@main
struct InstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Softswirl Web-Apps") { ContentView() }
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
}

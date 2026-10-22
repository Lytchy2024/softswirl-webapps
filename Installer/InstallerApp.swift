// Softswirl Web-Apps – Installer: zeigt die mitgelieferten WebKit-Apps, der Nutzer waehlt, was installiert und
// ins Dock gelegt wird. Kopiert nach ~/Applications und ergaenzt das Dock (com.apple.dock persistent-apps).
// Bauen: scripts/build_release.sh (swiftc -parse-as-library, SwiftUI, macOS 13+).
import SwiftUI
import AppKit

struct WebAppItem: Identifiable, Decodable, Hashable {
    let name: String
    let url: String
    let slug: String
    let description: String?
    var id: String { slug }
}

@MainActor
final class InstallerModel: ObservableObject {
    @Published var items: [WebAppItem] = []
    @Published var install: Set<String> = []
    @Published var dock: Set<String> = []
    @Published var busy = false
    @Published var finished = false
    @Published var status = ""
    @Published var log: [String] = []

    let appsDir: URL = Bundle.main.resourceURL!.appendingPathComponent("Apps", isDirectory: true)
    let targetDir: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    let logo: NSImage? = Bundle.main.url(forResource: "logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    init() {
        if let u = Bundle.main.url(forResource: "apps", withExtension: "json"), let d = try? Data(contentsOf: u),
           let list = try? JSONDecoder().decode([WebAppItem].self, from: d) {
            items = list.filter { FileManager.default.fileExists(atPath: bundledApp($0).path) }
        }
        install = Set(items.map { $0.slug }); dock = install
    }
    func bundledApp(_ item: WebAppItem) -> URL { appsDir.appendingPathComponent("\(item.name).app") }
    func installedApp(_ item: WebAppItem) -> URL { targetDir.appendingPathComponent("\(item.name).app") }
    func isInstalled(_ item: WebAppItem) -> Bool { FileManager.default.fileExists(atPath: installedApp(item).path) }
    func icon(_ item: WebAppItem) -> NSImage { NSWorkspace.shared.icon(forFile: bundledApp(item).path) }
    func selectAll(_ on: Bool) { install = on ? Set(items.map { $0.slug }) : []; dock = on ? install : [] }

    func run() {
        guard !busy else { return }
        busy = true; finished = false; log = []; status = "Installiere …"
        let chosen = items.filter { install.contains($0.slug) }
        let dockChosen = items.filter { dock.contains($0.slug) && install.contains($0.slug) }
        let appsDir = self.appsDir, targetDir = self.targetDir
        Task.detached { [weak self] in
            var lines: [String] = []
            let fm = FileManager.default
            do { try fm.createDirectory(at: targetDir, withIntermediateDirectories: true) } catch {}
            for item in chosen {
                let src = appsDir.appendingPathComponent("\(item.name).app")
                let dst = targetDir.appendingPathComponent("\(item.name).app")
                do {
                    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                    try fm.copyItem(at: src, to: dst)
                    lines.append("✓ \(item.name) installiert")
                } catch { lines.append("✗ \(item.name): \(error.localizedDescription)") }
            }
            if !dockChosen.isEmpty {
                let paths = dockChosen.map { targetDir.appendingPathComponent("\($0.name).app").path }
                InstallerModel.addToDock(paths: paths)
                lines.append("✓ \(dockChosen.count) Eintr\u{00E4}ge im Dock")
            }
            let result = lines
            await MainActor.run { [weak self] in
                self?.log = result; self?.busy = false; self?.finished = true
                self?.status = result.contains { $0.hasPrefix("✗") } ? "Fertig, mit Fehlern" : "Fertig"
            }
        }
    }

    /// Dock-Eintraege anhaengen (ohne Dubletten), dann Dock neu starten.
    nonisolated static func addToDock(paths: [String]) {
        let domain = "com.apple.dock" as CFString
        var apps = (CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]]) ?? []
        func urlString(_ p: String) -> String { URL(fileURLWithPath: p, isDirectory: true).absoluteString }
        let wanted = paths.map { urlString($0) }
        apps.removeAll { entry in
            guard let td = entry["tile-data"] as? [String: Any], let fd = td["file-data"] as? [String: Any],
                  let s = fd["_CFURLString"] as? String else { return false }
            return wanted.contains(s) || wanted.contains(s + "/")
        }
        for p in paths {
            apps.append(["tile-data": ["file-data": ["_CFURLString": urlString(p), "_CFURLStringType": 15]], "tile-type": "file-tile"])
        }
        CFPreferencesSetAppValue("persistent-apps" as CFString, apps as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["Dock"]
        try? p.run(); p.waitUntilExit()
    }
}

struct AppRow: View {
    @ObservedObject var model: InstallerModel
    let item: WebAppItem
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: model.icon(item)).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name).font(.headline)
                    if model.isInstalled(item) { Text("installiert").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
                }
                Text(item.description ?? item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Installieren", isOn: Binding(
                get: { model.install.contains(item.slug) },
                set: { on in if on { model.install.insert(item.slug) } else { model.install.remove(item.slug); model.dock.remove(item.slug) } }))
            Toggle("Ins Dock", isOn: Binding(
                get: { model.dock.contains(item.slug) },
                set: { on in if on { model.dock.insert(item.slug); model.install.insert(item.slug) } else { model.dock.remove(item.slug) } }))
                .disabled(!model.install.contains(item.slug))
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
    }
}

struct ContentView: View {
    @StateObject var model = InstallerModel()
    let gradient = LinearGradient(colors: [Color(red: 0.96, green: 0.65, blue: 0.78), Color(red: 0.66, green: 0.61, blue: 0.94)], startPoint: .bottomLeading, endPoint: .topTrailing)
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if let logo = model.logo { Image(nsImage: logo).resizable().interpolation(.high).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Softswirl Studio").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).textCase(.uppercase)
                    Text("Web-Apps installieren").font(.title.weight(.bold)).foregroundStyle(.white)
                    Text("Jede App läuft in ihrem eigenen Fenster mit eigener Anmeldung.").font(.callout).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(24)
            .background(Color(red: 0.086, green: 0.098, blue: 0.106))
            .overlay(alignment: .bottom) { Rectangle().fill(gradient).frame(height: 3) }

            ScrollView {
                VStack(spacing: 10) {
                    if model.items.isEmpty { Text("Keine Apps im Installer gefunden.").foregroundStyle(.secondary).padding() }
                    ForEach(model.items) { AppRow(model: model, item: $0) }
                }
                .padding(20)
            }

            Divider()
            HStack(spacing: 12) {
                Button("Alle") { model.selectAll(true) }
                Button("Keine") { model.selectAll(false) }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                if model.finished {
                    Button("Beenden") { NSApp.terminate(nil) }
                } else {
                    Button("Installieren") { model.run() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(model.busy || model.install.isEmpty)
                }
            }
            .padding(16)
            if model.finished {
                VStack(alignment: .leading, spacing: 4) { ForEach(model.log, id: \.self) { Text($0).font(.caption.monospaced()) } }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 600)
        .tint(Color(red: 0.66, green: 0.61, blue: 0.94))
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

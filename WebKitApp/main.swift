// WebKit-App-Huelle: eine eigenstaendige macOS-App pro Website (eigenes Fenster, eigene Cookies/Sitzung,
// Downloads, Datei-Upload, Popups, Druck, Zoom, Tastenkuerzel). Start-URL und Name kommen aus der Info.plist
// (WebAppStartURL, CFBundleDisplayName). Bauen: siehe build_webkit_apps.sh im selben Ordner.
import AppKit
import WebKit

final class WebAppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var windows: [NSWindow] = []
    var startURL = URL(string: "about:blank")!
    var appName = "WebApp"
    var downloadTargets: [ObjectIdentifier: URL] = [:]

    // MARK: Start
    func applicationDidFinishLaunching(_ note: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        appName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "WebApp"
        if let s = info["WebAppStartURL"] as? String, let u = URL(string: s) { startURL = u }
        buildMenu()
        openMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow() }
        return true
    }
    func openMainWindow() {
        let wv = makeWebView(configuration: nil)
        _ = makeWindow(for: wv, autosaveName: "HauptFenster")
        wv.load(URLRequest(url: startURL))
    }

    // MARK: WebView / Fenster
    func makeWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let config = configuration ?? {
            let c = WKWebViewConfiguration()
            c.websiteDataStore = .default()            // je App eigener Speicher (Cookies, Logins)
            c.preferences.javaScriptCanOpenWindowsAutomatically = true
            c.preferences.isFraudulentWebsiteWarningEnabled = true
            c.defaultWebpagePreferences.allowsContentJavaScript = true
            return c
        }()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.addObserver(self, forKeyPath: "title", options: [.new], context: nil)
        return wv
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "title", let wv = object as? WKWebView {
            let t = (wv.title ?? "").trimmingCharacters(in: .whitespaces)
            wv.window?.title = t.isEmpty ? appName : "\(t) – \(appName)"
        }
    }
    @discardableResult
    func makeWindow(for wv: WKWebView, autosaveName: String) -> NSWindow {
        let win = NSWindow(contentRect: wv.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = appName
        win.contentView = wv
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 480, height: 320)
        if !win.setFrameUsingName(autosaveName) { win.center() }
        win.setFrameAutosaveName(autosaveName)
        windows.append(win)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
            self?.windows.removeAll { $0 === win }
            (win.contentView as? WKWebView)?.removeObserver(self!, forKeyPath: "title")
        }
        win.makeKeyAndOrderFront(nil)
        return win
    }
    var currentWebView: WKWebView? { (NSApp.keyWindow ?? NSApp.mainWindow ?? windows.first)?.contentView as? WKWebView }

    // MARK: Navigation (Downloads erkennen)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "javascript", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)          // mailto:, tel: usw. ans System
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    func showLoadError(_ error: Error, in webView: WKWebView) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204) { return } // Frame-Load unterbrochen / Plugin
        let html = """
        <html><body style="font-family:-apple-system;padding:40px;color:#333"><h2>Seite nicht erreichbar</h2>
        <p>\(e.localizedDescription)</p><p><a href="\(startURL.absoluteString)">Erneut versuchen</a></p></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: Downloads
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        var target = dir.appendingPathComponent(suggestedFilename)
        let base = target.deletingPathExtension().lastPathComponent, ext = target.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1
        }
        downloadTargets[ObjectIdentifier(download)] = target
        completionHandler(target)
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let url = downloadTargets.removeValue(forKey: ObjectIdentifier(download)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadTargets.removeValue(forKey: ObjectIdentifier(download))
        let a = NSAlert(); a.messageText = "Download fehlgeschlagen"; a.informativeText = error.localizedDescription; a.runModal()
    }

    // MARK: Popups, Dialoge, Dateiauswahl
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let wv = makeWebView(configuration: configuration)
        makeWindow(for: wv, autosaveName: "PopupFenster")
        return wv
    }
    func webViewDidClose(_ webView: WKWebView) { webView.window?.close() }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = appName; a.informativeText = message; a.addButton(withTitle: "OK")
        a.beginSheetModal(for: webView.window ?? NSWindow()) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = appName; a.informativeText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Abbrechen")
        a.beginSheetModal(for: webView.window ?? NSWindow()) { r in completionHandler(r == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = appName; a.informativeText = prompt; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Abbrechen")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)); field.stringValue = defaultText ?? ""; a.accessoryView = field
        a.beginSheetModal(for: webView.window ?? NSWindow()) { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel(); p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = parameters.allowsDirectories; p.canChooseFiles = true
        p.beginSheetModal(for: webView.window ?? NSWindow()) { r in completionHandler(r == .OK ? p.urls : nil) }
    }

    // MARK: Menue und Aktionen
    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        appMenu.addItem(withTitle: "Über \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(appName) ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "\(appName) beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Bearbeiten"); let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = NSMenu(title: "Ansicht"); let viewItem = NSMenuItem(); viewItem.submenu = view; main.addItem(viewItem)
        view.addItem(withTitle: "Zurück", action: #selector(goBack), keyEquivalent: "[")
        view.addItem(withTitle: "Vorwärts", action: #selector(goForward), keyEquivalent: "]")
        view.addItem(withTitle: "Neu laden", action: #selector(reload), keyEquivalent: "r")
        view.addItem(withTitle: "Startseite", action: #selector(goHome), keyEquivalent: "H")
        view.addItem(.separator())
        view.addItem(withTitle: "Vergrößern", action: #selector(zoomIn), keyEquivalent: "+")
        view.addItem(withTitle: "Verkleinern", action: #selector(zoomOut), keyEquivalent: "-")
        view.addItem(withTitle: "Originalgröße", action: #selector(zoomReset), keyEquivalent: "0")
        view.addItem(.separator())
        view.addItem(withTitle: "Drucken …", action: #selector(printPage), keyEquivalent: "p")
        view.addItem(withTitle: "In Safari öffnen", action: #selector(openInSafari), keyEquivalent: "S")
        view.addItem(.separator())
        view.addItem(withTitle: "Website-Daten dieser App löschen …", action: #selector(clearData), keyEquivalent: "")

        let window = NSMenu(title: "Fenster"); let windowItem = NSMenuItem(); windowItem.submenu = window; main.addItem(windowItem)
        window.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Neues Fenster", action: #selector(newWindow), keyEquivalent: "n")
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
    @objc func goBack() { currentWebView?.goBack() }
    @objc func goForward() { currentWebView?.goForward() }
    @objc func reload() { currentWebView?.reload() }
    @objc func goHome() { currentWebView?.load(URLRequest(url: startURL)) }
    @objc func zoomIn() { if let w = currentWebView { w.pageZoom = min(w.pageZoom + 0.1, 3) } }
    @objc func zoomOut() { if let w = currentWebView { w.pageZoom = max(w.pageZoom - 0.1, 0.5) } }
    @objc func zoomReset() { currentWebView?.pageZoom = 1 }
    @objc func newWindow() { openMainWindow() }
    @objc func openInSafari() { if let u = currentWebView?.url ?? Optional(startURL) { NSWorkspace.shared.open(u) } }
    @objc func printPage() {
        guard let wv = currentWebView, let win = wv.window else { return }
        let op = wv.printOperation(with: NSPrintInfo.shared)
        op.view?.frame = wv.bounds
        op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func clearData() {
        let a = NSAlert(); a.messageText = "Website-Daten löschen?"; a.informativeText = "Cookies, Anmeldungen und Cache dieser App werden entfernt."
        a.addButton(withTitle: "Löschen"); a.addButton(withTitle: "Abbrechen")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in self?.goHome() }
    }
}

let app = NSApplication.shared
let delegate = WebAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

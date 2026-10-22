// Softswirl WebKit-App-Huelle: eine eigenstaendige macOS-App pro Website (eigenes Fenster, eigene Cookies/Sitzung,
// Downloads, Datei-Upload, Popups, Druck, Zoom, Tastenkuerzel), Symbolleiste mit Zurueck/Vorwaerts/Neu laden/Start,
// und ein eingebauter Passwortspeicher: Anmeldedaten werden im Schluesselbund des Nutzers abgelegt (iCloud-Schluesselbund,
// wenn verfuegbar) und auf Anmeldeseiten automatisch eingetragen. Start-URL und Name kommen aus der Info.plist
// (WebAppStartURL, CFBundleDisplayName). Bauen: scripts/build_release.sh.
import AppKit
import WebKit
import Security

// MARK: - Passwortspeicher (Schluesselbund)
struct Credential { let host: String; let user: String; let password: String }
enum Vault {
    static func baseDomain(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        return parts.count >= 2 ? parts.suffix(2).joined(separator: ".") : host.lowercased()
    }
    private static func query(host: String) -> [String: Any] {
        [kSecClass as String: kSecClassInternetPassword, kSecAttrServer as String: host,
         kSecUseDataProtectionKeychain as String: true, kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
    }
    static func load(host: String) -> [Credential] {
        var q = query(host: host); q[kSecReturnAttributes as String] = true; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { i in
            guard let u = i[kSecAttrAccount as String] as? String, let d = i[kSecValueData as String] as? Data, let p = String(data: d, encoding: .utf8) else { return nil }
            return Credential(host: host, user: u, password: p)
        }
    }
    /// Alle Eintraege, deren Domain zur aktuellen passt (www.x.de ↔ login.x.de).
    static func matching(host: String) -> [Credential] {
        var q: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecUseDataProtectionKeychain as String: true,
                                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny, kSecReturnAttributes as String: true,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        q[kSecAttrLabel as String] = label
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return [] }
        let base = baseDomain(host)
        return items.compactMap { i in
            guard let h = i[kSecAttrServer as String] as? String, baseDomain(h) == base, let u = i[kSecAttrAccount as String] as? String,
                  let d = i[kSecValueData as String] as? Data, let p = String(data: d, encoding: .utf8) else { return nil }
            return Credential(host: h, user: u, password: p)
        }.sorted { $0.host == host && $1.host != host }
    }
    static var label: String { "Softswirl Web-App: \(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "App")" }
    @discardableResult
    static func save(_ c: Credential) -> Bool {
        var q = query(host: c.host); q[kSecAttrAccount as String] = c.user
        let data = c.password.data(using: .utf8)!
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        var add = q; add[kSecValueData as String] = data; add[kSecAttrLabel as String] = label
        add[kSecAttrSynchronizable as String] = true            // iCloud-Schluesselbund, wenn aktiv
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var st = SecItemAdd(add as CFDictionary, nil)
        if st != errSecSuccess { add[kSecAttrSynchronizable as String] = false; st = SecItemAdd(add as CFDictionary, nil) }
        return st == errSecSuccess
    }
    static func delete(host: String, user: String) { var q = query(host: host); q[kSecAttrAccount as String] = user; SecItemDelete(q as CFDictionary) }
    static func deleteAll() {
        let q: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecUseDataProtectionKeychain as String: true,
                                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny, kSecAttrLabel as String: label]
        SecItemDelete(q as CFDictionary)
    }
}

let formScript = """
(function(){ if (window.__ssw) return; window.__ssw = true;
 function visible(el){ return !!(el && el.offsetParent !== null && !el.disabled); }
 function fields(){ const pws=[...document.querySelectorAll('input[type=password]')].filter(visible); const pw=pws[0]; if(!pw) return null;
   const inputs=[...document.querySelectorAll('input')]; const i=inputs.indexOf(pw); let user=null;
   for(let k=i-1;k>=0;k--){ const t=(inputs[k].type||'text').toLowerCase(); if(['text','email','tel','number'].includes(t) && visible(inputs[k])){ user=inputs[k]; break; } }
   return {user, pw}; }
 function setVal(el,v){ if(!el) return; const proto=Object.getPrototypeOf(el); const d=Object.getOwnPropertyDescriptor(proto,'value');
   (d&&d.set)?d.set.call(el,v):(el.value=v); el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); }
 window.__sswFill=function(u,p){ const f=fields(); if(!f) return false; if(f.user && !f.user.value) setVal(f.user,u); if(!f.pw.value) setVal(f.pw,p); return true; };
 window.__sswRead=function(){ const f=fields(); if(!f||!f.pw.value) return null; return {user:f.user?f.user.value:'', pass:f.pw.value}; };
 function report(){ const c=window.__sswRead(); if(c) window.webkit.messageHandlers.ssw.postMessage({type:'submit', user:c.user, pass:c.pass, host:location.host}); }
 document.addEventListener('submit', report, true);
 document.addEventListener('click', e=>{ const b=e.target && e.target.closest ? e.target.closest('button, input[type=submit], [role=button]') : null; if(b) report(); }, true);
 document.addEventListener('keydown', e=>{ if(e.key==='Enter' && e.target && e.target.tagName==='INPUT') report(); }, true);
 function announce(){ window.webkit.messageHandlers.ssw.postMessage({type:'loaded', hasPassword: !!fields(), host:location.host}); }
 announce(); let tries=0; const t=setInterval(()=>{ tries++; if(fields()){ announce(); clearInterval(t); } else if(tries>12) clearInterval(t); }, 500);
})();
"""

final class WebAppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, NSToolbarDelegate {
    var windows: [NSWindow] = []
    var startURL = URL(string: "about:blank")!
    var appName = "WebApp"
    var downloadTargets: [ObjectIdentifier: URL] = [:]
    var pendingSave: Credential?
    var askedThisPage: Set<String> = []
    var neverSave: Set<String> { get { Set(UserDefaults.standard.stringArray(forKey: "neverSaveHosts") ?? []) } set { UserDefaults.standard.set(Array(newValue), forKey: "neverSaveHosts") } }

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
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { openMainWindow() }; return true }
    func openMainWindow() { let wv = makeWebView(configuration: nil); makeWindow(for: wv, autosaveName: "HauptFenster"); wv.load(URLRequest(url: startURL)) }

    // MARK: WebView / Fenster
    func makeWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let config = configuration ?? {
            let c = WKWebViewConfiguration()
            c.websiteDataStore = .default()
            c.preferences.javaScriptCanOpenWindowsAutomatically = true
            c.preferences.isFraudulentWebsiteWarningEnabled = true
            c.defaultWebpagePreferences.allowsContentJavaScript = true
            return c
        }()
        config.userContentController.removeScriptMessageHandler(forName: "ssw")
        config.userContentController.add(self, name: "ssw")
        if !config.userContentController.userScripts.contains(where: { $0.source == formScript }) {
            config.userContentController.addUserScript(WKUserScript(source: formScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860), configuration: config)
        wv.navigationDelegate = self; wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true; wv.allowsMagnification = true
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
        win.title = appName; win.contentView = wv; win.isReleasedWhenClosed = false; win.minSize = NSSize(width: 480, height: 320)
        win.toolbarStyle = .unified
        let tb = NSToolbar(identifier: "ssw.toolbar"); tb.delegate = self; tb.displayMode = .iconOnly; tb.allowsUserCustomization = false
        win.toolbar = tb
        if !win.setFrameUsingName(autosaveName) { win.center() }
        win.setFrameAutosaveName(autosaveName)
        windows.append(win)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.windows.removeAll { $0 === win }
            (win.contentView as? WKWebView)?.removeObserver(self, forKeyPath: "title")
        }
        win.makeKeyAndOrderFront(nil)
        return win
    }
    var currentWebView: WKWebView? { (NSApp.keyWindow ?? NSApp.mainWindow ?? windows.first)?.contentView as? WKWebView }

    // MARK: Symbolleiste
    let tbItems: [NSToolbarItem.Identifier] = [.init("back"), .init("forward"), .init("reload"), .init("home"), .flexibleSpace, .init("passwords")]
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tbItems }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tbItems }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let spec: [String: (String, String, Selector)] = [
            "back": ("chevron.left", "Zurück", #selector(goBack)), "forward": ("chevron.right", "Vorwärts", #selector(goForward)),
            "reload": ("arrow.clockwise", "Neu laden", #selector(reload)), "home": ("house", "Startseite", #selector(goHome)),
            "passwords": ("key.fill", "Gespeicherte Anmeldungen", #selector(showPasswordsMenu(_:))),
        ]
        guard let (sym, label, sel) = spec[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label; item.toolTip = label; item.isBordered = true
        item.image = NSImage(systemSymbolName: sym, accessibilityDescription: label)
        item.target = self; item.action = sel
        return item
    }

    // MARK: Navigation
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(), !["http", "https", "about", "blob", "data", "javascript", "file"].contains(scheme) {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { askedThisPage.removeAll() }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    func showLoadError(_ error: Error, in webView: WKWebView) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204) { return }
        let html = "<html><body style=\"font-family:-apple-system;padding:40px;color:#333\"><h2>Seite nicht erreichbar</h2><p>\(e.localizedDescription)</p><p><a href=\"\(startURL.absoluteString)\">Erneut versuchen</a></p></body></html>"
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: Passwoerter: Nachrichten aus der Seite
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String, let wv = message.webView else { return }
        let host = (body["host"] as? String) ?? wv.url?.host ?? ""
        switch type {
        case "loaded":
            guard (body["hasPassword"] as? Bool) == true, let c = Vault.matching(host: host).first else { return }
            let js = "window.__sswFill(\(jsString(c.user)), \(jsString(c.password)))"
            wv.evaluateJavaScript(js, completionHandler: nil)
        case "submit":
            guard let user = body["user"] as? String, let pass = body["pass"] as? String, !pass.isEmpty, !host.isEmpty else { return }
            if neverSave.contains(Vault.baseDomain(host)) { return }
            let existing = Vault.load(host: host)
            if existing.contains(where: { $0.user == user && $0.password == pass }) { return }
            let key = "\(host)|\(user)"
            if askedThisPage.contains(key) { return }
            askedThisPage.insert(key)
            pendingSave = Credential(host: host, user: user, password: pass)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.offerSave(in: wv) }
        default: break
        }
    }
    func jsString(_ s: String) -> String {
        let d = try? JSONSerialization.data(withJSONObject: [s]); let a = d.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(a.dropFirst().dropLast())
    }
    func offerSave(in wv: WKWebView) {
        guard let c = pendingSave, let win = wv.window else { return }
        pendingSave = nil
        let update = Vault.load(host: c.host).contains { $0.user == c.user }
        let a = NSAlert(); a.messageText = update ? "Passwort für \(c.host) aktualisieren?" : "Passwort für \(c.host) speichern?"
        a.informativeText = "Benutzer: \(c.user.isEmpty ? "(ohne Benutzername)" : c.user)\nGespeichert wird im Schlüsselbund dieses Macs (mit iCloud-Schlüsselbund auf allen deinen Geräten). Beim nächsten Besuch wird die Anmeldung automatisch eingetragen."
        a.addButton(withTitle: update ? "Aktualisieren" : "Speichern"); a.addButton(withTitle: "Nicht jetzt"); a.addButton(withTitle: "Nie für diese Website")
        a.beginSheetModal(for: win) { r in
            switch r {
            case .alertFirstButtonReturn: if !Vault.save(c) { self.toast("Speichern im Schlüsselbund fehlgeschlagen") }
            case .alertThirdButtonReturn: var n = self.neverSave; n.insert(Vault.baseDomain(c.host)); self.neverSave = n
            default: break
            }
        }
    }
    func toast(_ s: String) { let a = NSAlert(); a.messageText = appName; a.informativeText = s; a.runModal() }
    @objc func showPasswordsMenu(_ sender: Any?) {
        guard let wv = currentWebView, let host = wv.url?.host else { return }
        let menu = NSMenu()
        let creds = Vault.matching(host: host)
        if creds.isEmpty { menu.addItem(withTitle: "Keine gespeicherte Anmeldung für \(host)", action: nil, keyEquivalent: "") }
        for c in creds {
            let it = NSMenuItem(title: "Eintragen: \(c.user.isEmpty ? "(ohne Benutzername)" : c.user)", action: #selector(fillCredential(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = [c.host, c.user]; menu.addItem(it)
        }
        menu.addItem(.separator())
        let save = NSMenuItem(title: "Aktuelle Eingaben speichern …", action: #selector(saveCurrent), keyEquivalent: ""); save.target = self; menu.addItem(save)
        if !creds.isEmpty {
            let del = NSMenuItem(title: "Anmeldung für \(host) löschen …", action: #selector(deleteForHost), keyEquivalent: ""); del.target = self; menu.addItem(del)
        }
        if neverSave.contains(Vault.baseDomain(host)) {
            let again = NSMenuItem(title: "Für diese Website wieder nachfragen", action: #selector(forgetNever), keyEquivalent: ""); again.target = self; menu.addItem(again)
        }
        if let item = sender as? NSToolbarItem, let v = item.view ?? wv.window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: v.bounds.height), in: v)
        } else if let v = (sender as? NSView) ?? wv.window?.contentView { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: v.bounds.height), in: v) }
    }
    @objc func fillCredential(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [String], arr.count == 2, let wv = currentWebView else { return }
        if let c = Vault.load(host: arr[0]).first(where: { $0.user == arr[1] }) {
            wv.evaluateJavaScript("window.__sswFill && (function(){ const f=window.__sswRead; return window.__sswFill(\(jsString(c.user)), \(jsString(c.password))); })()", completionHandler: nil)
        }
    }
    @objc func saveCurrent() {
        guard let wv = currentWebView, let host = wv.url?.host else { return }
        wv.evaluateJavaScript("window.__sswRead ? window.__sswRead() : null") { [weak self] res, _ in
            guard let self = self else { return }
            guard let d = res as? [String: Any], let pass = d["pass"] as? String, !pass.isEmpty else { self.toast("Auf dieser Seite ist kein ausgefülltes Passwortfeld sichtbar."); return }
            self.pendingSave = Credential(host: host, user: (d["user"] as? String) ?? "", password: pass)
            self.offerSave(in: wv)
        }
    }
    @objc func deleteForHost() {
        guard let wv = currentWebView, let host = wv.url?.host else { return }
        let a = NSAlert(); a.messageText = "Gespeicherte Anmeldung für \(host) löschen?"; a.addButton(withTitle: "Löschen"); a.addButton(withTitle: "Abbrechen")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for c in Vault.matching(host: host) { Vault.delete(host: c.host, user: c.user) }
    }
    @objc func forgetNever() { guard let host = currentWebView?.url?.host else { return }; var n = neverSave; n.remove(Vault.baseDomain(host)); neverSave = n }

    // MARK: Downloads
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        var target = dir.appendingPathComponent(suggestedFilename)
        let base = target.deletingPathExtension().lastPathComponent, ext = target.pathExtension; var n = 2
        while FileManager.default.fileExists(atPath: target.path) { target = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1 }
        downloadTargets[ObjectIdentifier(download)] = target; completionHandler(target)
    }
    func downloadDidFinish(_ download: WKDownload) { if let url = downloadTargets.removeValue(forKey: ObjectIdentifier(download)) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { downloadTargets.removeValue(forKey: ObjectIdentifier(download)); toast("Download fehlgeschlagen: \(error.localizedDescription)") }

    // MARK: Popups, Dialoge, Dateiauswahl
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let wv = makeWebView(configuration: configuration); makeWindow(for: wv, autosaveName: "PopupFenster"); return wv
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
        let p = NSOpenPanel(); p.allowsMultipleSelection = parameters.allowsMultipleSelection; p.canChooseDirectories = parameters.allowsDirectories; p.canChooseFiles = true
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
        let pw = NSMenu(title: "Anmeldung"); let pwItem = NSMenuItem(); pwItem.submenu = pw; main.addItem(pwItem)
        pw.addItem(withTitle: "Gespeicherte Anmeldungen …", action: #selector(showPasswordsMenu(_:)), keyEquivalent: "k")
        pw.addItem(withTitle: "Aktuelle Eingaben speichern …", action: #selector(saveCurrent), keyEquivalent: "")
        pw.addItem(withTitle: "Anmeldung dieser Website löschen …", action: #selector(deleteForHost), keyEquivalent: "")
        pw.addItem(.separator())
        pw.addItem(withTitle: "Website-Daten dieser App löschen …", action: #selector(clearData), keyEquivalent: "")
        let window = NSMenu(title: "Fenster"); let windowItem = NSMenuItem(); windowItem.submenu = window; main.addItem(windowItem)
        window.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Neues Fenster", action: #selector(newWindow), keyEquivalent: "n")
        NSApp.mainMenu = main; NSApp.windowsMenu = window
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
        let op = wv.printOperation(with: NSPrintInfo.shared); op.view?.frame = wv.bounds
        op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil)
    }
    @objc func clearData() {
        let a = NSAlert(); a.messageText = "Website-Daten löschen?"; a.informativeText = "Cookies, Sitzung und Cache dieser App werden entfernt. Gespeicherte Anmeldungen im Schlüsselbund bleiben erhalten."
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

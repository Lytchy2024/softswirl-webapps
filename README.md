# Softswirl Web-Apps

Eigenständige macOS-Apps für Web-Portale: jede App öffnet ihre Website in einem eigenen Fenster mit eigener
Anmeldung und eigenen Cookies (WebKit, dieselbe Engine wie Safari), dazu ein Installer, der die gewünschten Apps
nach `~/Applications` kopiert und ins Dock legt.

## Benutzen

1. Aus den [Releases](../../releases) das DMG `Softswirl-Web-Apps-<version>.dmg` laden und öffnen.
2. `Softswirl Web-Apps.app` starten. Das Fenster listet alle mitgelieferten Apps.
3. Bei jeder App „Installieren" und „Ins Dock" an- oder abwählen, dann **Installieren**.
4. Fertig: die Apps liegen in `~/Applications`, das Dock zeigt sie. Vorhandene Versionen werden ersetzt.

Das DMG und alle Apps sind mit Developer ID signiert und von Apple notarisiert, es erscheint keine Warnung.

## Was jede Web-App kann

Eigenes Fenster (merkt sich Größe und Lage), eigene Sitzung je App, Downloads nach „Downloads" mit Anzeige im Finder,
Datei-Upload, Popups als eigene Fenster, JavaScript-Dialoge, Drucken (⌘P), Zoom (⌘+ ⌘- ⌘0), Zurück/Vorwärts (⌘[ ⌘]),
Neu laden (⌘R), Startseite (⌘⇧H), „In Safari öffnen" (⌘⇧S), „Website-Daten dieser App löschen".
Nicht enthalten: Passwort-Autofill aus dem iCloud-Schlüsselbund (nur Safari) und Web-Push.

## Apps hinzufügen

`apps.json` um einen Eintrag ergänzen (`name`, `slug`, `url`, optional `letters` für ein Buchstaben-Icon und
`description`). Ein Icon als `icons/<name>.icns` ablegen; fehlt es, erzeugt der Build ein Buchstaben-Icon.
Dann ein neues Release bauen.

## Release bauen

Voraussetzungen: macOS mit Xcode (swiftc, codesign, notarytool), Developer-ID-Zertifikat im Schlüsselbund und ein
notarytool-Profil (`xcrun notarytool store-credentials <profil> --apple-id … --team-id …`).

```bash
SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=<profil> scripts/build_release.sh --version 1.0.0
gh release create v1.0.0 dist/Softswirl-Web-Apps-1.0.0.dmg --title "Softswirl Web-Apps 1.0.0"
```

Ohne Zertifikat: `scripts/build_release.sh --adhoc` (nur lokal, unsigniert im Sinne von Gatekeeper).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `WebKitApp/main.swift` | die App-Hülle (AppKit + WKWebView), Start-URL aus `WebAppStartURL` in der Info.plist |
| `Installer/InstallerApp.swift` | der Installer (SwiftUI): Auswahl, Kopie nach `~/Applications`, Dock-Einträge |
| `apps.json` | Liste der Apps |
| `icons/` | Icons (`<name>.icns`), `logo.png` für Installer und Kopfzeile |
| `scripts/build_release.sh` | Build, Signatur, Notarisierung, DMG |
| `scripts/make_letter_icon.swift` | Buchstaben-Icons für Apps ohne eigenes Icon |

© Softswirl Studio

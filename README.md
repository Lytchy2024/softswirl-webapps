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

## Programme

Neben den Web-Apps installiert der Installer auch Programme fürs Gerät:

* **TeamViewer QuickSupport** – offizieller Download, Prüfung der Developer-ID-Signatur (TeamViewer Germany GmbH) und der
  Notarisierung, Kopie nach `/Applications`.
* **Bitdefender** – Download-Link aus Bitdefender Central einfügen (der Installer öffnet die Seite, dort auf Herunterladen
  klicken) oder ein vorhandenes `.pkg` wählen; Prüfung der Paketsignatur (Bitdefender SRL), Installation mit Admin-Passwort.
  Die Freigaben in den Systemeinstellungen (Erweiterungen, Festplattenzugriff) bleiben Handarbeit.

Installierte Apps bekommen das Quarantäne-Flag entfernt, damit nicht jede beim ersten Start einzeln nachfragt; alle sind
vorher signiert und notarisiert.

## Was jede Web-App kann

Symbolleiste mit Zurück, Vorwärts, Neu laden, **Startseite** und einem Schlüssel-Knopf für gespeicherte Anmeldungen.
**Eingebauter Passwortspeicher:** Beim Anmelden fragt die App, ob sie Benutzername und Passwort für die Website speichern
soll (im Anmelde-Schlüsselbund dieses Macs; iCloud-Abgleich bräuchte ein Developer-ID-Profil mit Keychain Sharing, siehe unten). Beim nächsten Besuch trägt sie
die Anmeldung automatisch ein; mehrere Konten lassen sich über den Schlüssel-Knopf wählen. „Nie für diese Website" wird
gemerkt. Hinweis: Apples Passwörter-App kann in WebKit-Apps von Drittanbietern weder ausfüllen noch speichern, das geht nur
in Safari und Safari-Web-Apps; deshalb hat die App ihren eigenen Speicher im Schlüsselbund.
Links derselben Website, die ein neues Fenster öffnen wollen, laden im selben Fenster (Zurück führt zurück); echte Popups bekommen ein eigenes Fenster. Eigenes Fenster (merkt sich Größe und Lage), eigene Sitzung je App, Downloads nach „Downloads" mit Anzeige im Finder,
Datei-Upload, Popups als eigene Fenster, JavaScript-Dialoge, Drucken (⌘P), Zoom (⌘+ ⌘- ⌘0), Zurück/Vorwärts (⌘[ ⌘]),
Neu laden (⌘R), Startseite (⌘⇧H), „In Safari öffnen" (⌘⇧S), „Website-Daten dieser App löschen".
Nicht enthalten: Web-Push und Passkeys.

## Apps hinzufügen

`apps.json` um einen Eintrag ergänzen (`name`, `slug`, `url`, optional `letters` für ein Buchstaben-Icon und
`description`; Programme mit `kind` = `dmgapp` (`url`, `appName`, `teamId`) oder `pkgwatch` (`signer`, `pkgMatch`)). Ein Icon als `icons/<name>.icns` ablegen; fehlt es, erzeugt der Build ein Buchstaben-Icon.
Dann ein neues Release bauen.

## Release bauen

Voraussetzungen: macOS mit Xcode (swiftc, codesign, notarytool), Developer-ID-Zertifikat im Schlüsselbund und ein
notarytool-Profil (`xcrun notarytool store-credentials <profil> --apple-id … --team-id …`).

```bash
SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=<profil> scripts/build_release.sh --version 1.0.0
gh release create v1.0.0 dist/Softswirl-Web-Apps-1.0.0.dmg --title "Softswirl Web-Apps 1.0.0"
```

Ohne Zertifikat: `scripts/build_release.sh --adhoc` (nur lokal, unsigniert im Sinne von Gatekeeper).

## iCloud-Abgleich der gespeicherten Anmeldungen (optional, nicht eingerichtet)

Der Passwortspeicher nutzt den Anmelde-Schlüsselbund des Macs. Damit Einträge über den iCloud-Schlüsselbund auf andere
Geräte gelangen, bräuchten die Apps den Data-Protection-Keychain, und dafür ein Developer-ID-Provisioning-Profil mit der
Capability „Keychain Sharing" (Entwicklerportal → Identifiers → App-ID je App → Profil erzeugen, im Bundle als
`embedded.provisionprofile`, Entitlement `keychain-access-groups`). Ohne Profil liefert SecItemAdd Fehler -34018.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `WebKitApp/main.swift` | die App-Hülle (AppKit + WKWebView), Start-URL aus `WebAppStartURL` in der Info.plist |
| `Installer/InstallerApp.swift` | der Installer (SwiftUI): Auswahl, Kopie nach `~/Applications`, Dock-Einträge |
| `apps.json` | Liste der Apps |
| `icons/` | Icons (`<name>.icns`), `logo.png` für Installer und Kopfzeile |
| `scripts/build_release.sh` | Build, Signatur, Notarisierung, DMG |
| `scripts/make_letter_icon.swift` | Buchstaben-Icons für Apps ohne eigenes Icon |
| `scripts/make_image_icon.swift` | Icon aus einem Logo-Bild (zentriert, Rand, abgerundeter Hintergrund) |

© Softswirl Studio

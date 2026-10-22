#!/bin/bash
# Softswirl Web-Apps – Release bauen: WebKit-Apps aus apps.json, Installer-App, Signatur, Notarisierung, DMG.
#
#   scripts/build_release.sh [--version 1.0.0] [--no-notarize] [--adhoc]
#
# Umgebung (optional):
#   SIGN_ID         Developer-ID-Identitaet, z. B. "Developer ID Application: Name (TEAMID)"  (ohne: ad hoc, nicht notarisierbar)
#   NOTARY_PROFILE  notarytool-Schluesselbundprofil (xcrun notarytool store-credentials <profil> ...)
# Ergebnis: dist/Softswirl-Web-Apps-<version>.dmg (signiert, notarisiert, gestapelt), dist/Softswirl Web-Apps.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.1.0"; NOTARIZE=1; ADHOC=0
while [ $# -gt 0 ]; do case "$1" in --version) VERSION="$2"; shift;; --no-notarize) NOTARIZE=0;; --adhoc) ADHOC=1;; *) echo "unbekannt: $1"; exit 1;; esac; shift; done
SIGN_ID="${SIGN_ID:-}"; NOTARY_PROFILE="${NOTARY_PROFILE:-}"
[ -n "$SIGN_ID" ] || ADHOC=1
[ $ADHOC -eq 1 ] && NOTARIZE=0
BUILD="$ROOT/build"; DIST="$ROOT/dist"; rm -rf "$BUILD"; mkdir -p "$BUILD" "$DIST"
ARCHS=(x86_64 arm64)
sign() { # sign <pfad> [entitlements]
  if [ $ADHOC -eq 1 ]; then codesign --force -s - "$1" >/dev/null 2>&1
  else codesign --force --options runtime --timestamp ${2:+--entitlements "$2"} -s "$SIGN_ID" "$1"; fi
}

echo "== 1. WebKit-Huelle (${ARCHS[*]})"
BINS=(); for a in "${ARCHS[@]}"; do swiftc -O -target "$a-apple-macos13.0" -framework AppKit -framework WebKit -o "$BUILD/shell-$a" "$ROOT/WebKitApp/main.swift"; BINS+=("$BUILD/shell-$a"); done
lipo -create "${BINS[@]}" -output "$BUILD/shell"
swiftc -O -framework AppKit -o "$BUILD/mkicon" "$ROOT/scripts/make_letter_icon.swift"
cat > "$BUILD/webapp.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT

echo "== 2. Web-Apps aus apps.json"
APPS="$BUILD/apps"; mkdir -p "$APPS"
python3 - "$ROOT/apps.json" <<'PY' > "$BUILD/apps.tsv"
import json, sys
for a in json.load(open(sys.argv[1])): print("\t".join([a["name"], a["url"], a["slug"], a.get("letters", a["name"][:2])]))
PY
while IFS=$'\t' read -r NAME URL SLUG LETTERS; do
  APP="$APPS/$NAME.app"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BUILD/shell" "$APP/Contents/MacOS/$SLUG"
  ICN="$ROOT/icons/$NAME.icns"
  if [ ! -f "$ICN" ]; then
    "$BUILD/mkicon" "$LETTERS" "$BUILD/$SLUG.png" >/dev/null; rm -rf "$BUILD/$SLUG.iconset"; mkdir -p "$BUILD/$SLUG.iconset"
    for s in 16 32 128 256 512; do sips -z $s $s "$BUILD/$SLUG.png" --out "$BUILD/$SLUG.iconset/icon_${s}x${s}.png" >/dev/null; sips -z $((s*2)) $((s*2)) "$BUILD/$SLUG.png" --out "$BUILD/$SLUG.iconset/icon_${s}x${s}@2x.png" >/dev/null; done
    iconutil -c icns "$BUILD/$SLUG.iconset" -o "$ICN"; echo "   Buchstaben-Icon: $NAME ($LETTERS)"
  fi
  cp "$ICN" "$APP/Contents/Resources/AppIcon.icns"; printf 'APPL????' > "$APP/Contents/PkgInfo"
  cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>de</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleExecutable</key><string>$SLUG</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>lu.softswirlstudio.webapp.$SLUG</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSApplicationCategoryType</key><string>public.app-category.business</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSSupportsAutomaticTermination</key><false/>
<key>NSCameraUsageDescription</key><string>Nur falls die Website die Kamera anfordert.</string>
<key>NSMicrophoneUsageDescription</key><string>Nur falls die Website das Mikrofon anfordert.</string>
<key>NSHumanReadableCopyright</key><string>© Softswirl Studio</string>
<key>WebAppStartURL</key><string>$URL</string>
</dict></plist>
PL
  sign "$APP" "$BUILD/webapp.entitlements"; echo "   $NAME.app"
done < "$BUILD/apps.tsv"

if [ $NOTARIZE -eq 1 ]; then
  [ -n "$NOTARY_PROFILE" ] || { echo "NOTARY_PROFILE fehlt"; exit 1; }
  echo "== 2b. Web-Apps einzeln notarisieren (parallel einreichen, dann warten, dann stapeln)"
  IDS=(); NAMES=()
  while IFS=$'\t' read -r NAME URL SLUG LETTERS; do
    ditto -c -k --keepParent "$APPS/$NAME.app" "$BUILD/$SLUG.zip"
    ID=$(xcrun notarytool submit "$BUILD/$SLUG.zip" --keychain-profile "$NOTARY_PROFILE" --output-format json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    IDS+=("$ID"); NAMES+=("$NAME"); echo "   eingereicht: $NAME ($ID)"
  done < "$BUILD/apps.tsv"
  for i in "${!IDS[@]}"; do
    ST=$(xcrun notarytool wait "${IDS[$i]}" --keychain-profile "$NOTARY_PROFILE" --output-format json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
    [ "$ST" = "Accepted" ] || { echo "Notarisierung fehlgeschlagen: ${NAMES[$i]} ($ST)"; xcrun notarytool log "${IDS[$i]}" --keychain-profile "$NOTARY_PROFILE"; exit 1; }
    xcrun stapler staple "$APPS/${NAMES[$i]}.app" >/dev/null && echo "   notarisiert + gestapelt: ${NAMES[$i]}"
  done
fi

echo "== 3. Installer-App"
INST="$DIST/Softswirl Web-Apps.app"; rm -rf "$INST"; mkdir -p "$INST/Contents/MacOS" "$INST/Contents/Resources/Apps"
BINS=(); for a in "${ARCHS[@]}"; do swiftc -O -parse-as-library -target "$a-apple-macos13.0" -framework SwiftUI -framework AppKit -o "$BUILD/installer-$a" "$ROOT/Installer/InstallerApp.swift"; BINS+=("$BUILD/installer-$a"); done
lipo -create "${BINS[@]}" -output "$INST/Contents/MacOS/SoftswirlWebApps"
cp -R "$APPS/"*.app "$INST/Contents/Resources/Apps/"
cp "$ROOT/apps.json" "$ROOT/icons/logo.png" "$INST/Contents/Resources/"
rm -rf "$BUILD/logo.iconset"; mkdir -p "$BUILD/logo.iconset"
for s in 16 32 128 256 512; do sips -z $s $s "$ROOT/icons/logo.png" --out "$BUILD/logo.iconset/icon_${s}x${s}.png" >/dev/null; sips -z $((s*2)) $((s*2)) "$ROOT/icons/logo.png" --out "$BUILD/logo.iconset/icon_${s}x${s}@2x.png" >/dev/null; done
iconutil -c icns "$BUILD/logo.iconset" -o "$INST/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$INST/Contents/PkgInfo"
cat > "$INST/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>de</string>
<key>CFBundleDisplayName</key><string>Softswirl Web-Apps</string>
<key>CFBundleExecutable</key><string>SoftswirlWebApps</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>lu.softswirlstudio.webapps.installer</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Softswirl Web-Apps</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>© Softswirl Studio</string>
</dict></plist>
PL
sign "$INST"
codesign --verify --deep --strict "$INST" && echo "   Signatur geprueft ($([ $ADHOC -eq 1 ] && echo 'ad hoc' || echo "$SIGN_ID"))"

if [ $NOTARIZE -eq 1 ]; then
  [ -n "$NOTARY_PROFILE" ] || { echo "NOTARY_PROFILE fehlt"; exit 1; }
  echo "== 4. Notarisierung der App"
  ditto -c -k --keepParent "$INST" "$BUILD/installer.zip"
  xcrun notarytool submit "$BUILD/installer.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$INST"
fi

echo "== 5. DMG"
STAGE="$BUILD/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$INST" "$STAGE/"
DMG="$DIST/Softswirl-Web-Apps-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "Softswirl Web-Apps" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
[ $ADHOC -eq 1 ] || codesign --force --timestamp -s "$SIGN_ID" "$DMG"
if [ $NOTARIZE -eq 1 ]; then
  echo "== 6. Notarisierung des DMG"; xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait; xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -1
fi
echo "fertig: $DMG ($(du -h "$DMG" | cut -f1))"

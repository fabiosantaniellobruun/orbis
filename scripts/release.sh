#!/bin/bash
#
# Prepara Orbis per la distribuzione: compila in Release, firma, crea il DMG e, se ci sono le
# credenziali, lo notarizza. Il risultato sta in dist/.
#
#   scripts/release.sh
#
# Senza credenziali (la scelta attuale) produce un DMG firmato "ad hoc": su un altro Mac Gatekeeper
# lo blocca finché l'utente non lo autorizza una volta, come spiega il README. Con un Developer ID
# e la notarizzazione l'avviso sparisce (vedi docs/RELEASING.md).
#
# Variabili d'ambiente:
#   DEVELOPER_ID    l'identità di firma, per esempio
#                   "Developer ID Application: Nome Cognome (ABCDE12345)"
#   NOTARY_PROFILE  il profilo di notarytool nel portachiavi, creato con
#                   xcrun notarytool store-credentials "orbis-notary" …
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Orbis.xcodeproj"
SCHEME="Orbis"
APP_NAME="Orbis"
BUILD_DIR="build/release"
DIST_DIR="dist"
IDENTITY="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# MARK: Versione

VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^ *MARKETING_VERSION = / { print $2; exit }')"
[ -n "$VERSION" ] || fail "Non riesco a leggere la versione dal progetto."

APP="$DIST_DIR/$APP_NAME.app"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [ -n "$IDENTITY" ]; then
  security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
    || fail "L'identità \"$IDENTITY\" non è nel portachiavi. Controlla con: security find-identity -v -p codesigning"
  SIGN_FLAGS=(--timestamp --options runtime)
  SIGN_IDENTITY="$IDENTITY"
else
  warn "DEVELOPER_ID non impostata: firma ad hoc, nessuna notarizzazione."
  SIGN_FLAGS=(--options runtime)
  SIGN_IDENTITY="-"
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# MARK: Compilazione

step "Compilo Orbis $VERSION (Release)"
# Il registro completo va su file: xcodebuild è molto rumoroso, e lo si legge solo se qualcosa va storto.
if ! xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="${SIGN_FLAGS[*]}" \
  ENABLE_HARDENED_RUNTIME=YES \
  > "$BUILD_DIR/xcodebuild.log" 2>&1; then
  grep -E "error:" "$BUILD_DIR/xcodebuild.log" | head -20 >&2 || true
  fail "La compilazione è fallita. Registro completo: $BUILD_DIR/xcodebuild.log"
fi

ARCHIVED_APP="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
[ -d "$ARCHIVED_APP" ] || fail "La compilazione non ha prodotto $APP_NAME.app."
cp -R "$ARCHIVED_APP" "$APP"

# MARK: Controlli sull'app

step "Controllo la firma"
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Runtime|Signature" || true

step "Architetture e requisiti"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist" | sed 's/^/macOS minimo: /'
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" | sed 's/^/Versione: /'

# MARK: Notarizzazione dell'app

if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  step "Notarizzo l'app"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"
  xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
elif [ -n "$IDENTITY" ]; then
  warn "NOTARY_PROFILE non impostata: l'app è firmata ma non notarizzata."
fi

# MARK: DMG

step "Creo il DMG"
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# hdiutil segnala che `create` è "deprecato", ma funziona e non richiede altro: si toglie l'avviso.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" 2>&1 | grep -v "deprecated" || true
[ -f "$DMG" ] || fail "Non sono riuscito a creare il DMG."

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

# MARK: Notarizzazione del DMG

if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  step "Notarizzo il DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"

  step "Verifico come la vedrebbe Gatekeeper"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

# MARK: Risultato

# Con un nome che non cambia, il link "ultima versione" di GitHub Releases resta sempre lo stesso.
cp "$DMG" "$DIST_DIR/$APP_NAME.dmg"

step "Fatto"
( cd "$DIST_DIR" && shasum -a 256 "$APP_NAME-$VERSION.dmg" | tee "$APP_NAME-$VERSION.dmg.sha256" )
printf '\n  %s\n  %s (stessa cosa, con il nome fisso per il link "ultima versione")\n' "$DMG" "$DIST_DIR/$APP_NAME.dmg"

if [ -z "$IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
  printf '\n'
  warn "DMG non notarizzato: al primo avvio chi lo scarica deve autorizzare Orbis una volta"
  warn "(Privacy e sicurezza → Apri comunque, come spiega il README). Per notarizzarlo: docs/RELEASING.md."
fi

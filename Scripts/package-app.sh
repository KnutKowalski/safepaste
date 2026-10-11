#!/bin/bash
# Baut aus dem SPM-Release-Binary ein SafePaste.app-Bundle (ad-hoc signiert).
set -euo pipefail

APP_NAME="SafePaste"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/.build/release/SafePaste"
[ -x "$BIN" ] || BIN="$ROOT/.build/release/safe-paste"
[ -x "$BIN" ] || { echo "Fehler: kein Release-Binary. Zuerst 'swift build -c release' ausführen."; exit 1; }

APP="$ROOT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc-Signatur (kein Apple-Developer-Account nötig; lokale Ausführung).
codesign --force --sign - "$APP"

echo "App verpackt: $APP"
ditto -c -k --keepParent "$APP" "$ROOT/SafePaste.app.zip"
echo "Zip erstellt: $ROOT/SafePaste.app.zip"

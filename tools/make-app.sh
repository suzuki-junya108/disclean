#!/bin/bash
# Disclean.app を組み立てる。SwiftPM の実行ファイルにバンドル構造を被せる方式。
# 使い方: tools/make-app.sh [--universal] [--sign <identity>] [--preview]
#   --preview は画面確認用のビルド（起動時に DISCLEAN_PREVIEW の画面を開く）。
#   配布物には使わない。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_ARGS=(-c release)
SIGN_IDENTITY=""
UNIVERSAL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --universal) UNIVERSAL=1; shift ;;
        --preview) BUILD_ARGS+=(-Xswiftc -DUI_PREVIEW); shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ "$UNIVERSAL" = 1 ]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> building DiscleanApp"
swift build "${BUILD_ARGS[@]}" --product DiscleanApp

if [ "$UNIVERSAL" = 1 ]; then
    BIN="$ROOT/.build/apple/Products/Release/DiscleanApp"
    BUNDLE_SRC="$ROOT/.build/apple/Products/Release/Disclean_DiscleanKit.bundle"
else
    BIN="$ROOT/.build/release/DiscleanApp"
    BUNDLE_SRC="$ROOT/.build/release/Disclean_DiscleanKit.bundle"
fi

APP="$ROOT/build/Disclean.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Disclean"
# 同梱ルールと公開鍵は DiscleanKit のリソースバンドルに入っている。
[ -d "$BUNDLE_SRC" ] && cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"

VERSION="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/DiscleanKit/Version.swift | head -1 | tr -d '"')"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Disclean</string>
    <key>CFBundleDisplayName</key><string>ディスクリン</string>
    <key>CFBundleIdentifier</key><string>jp.i4u.disclean</string>
    <key>ATSApplicationFontsPath</key><string>fonts</string>
    <key>CFBundleExecutable</key><string>Disclean</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

[ -f "$ROOT/build/AppIcon.icns" ] && cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 書体を同梱する。入っていないと、意図した字面（重さ・幅）にならない。
mkdir -p "$APP/Contents/Resources/LICENSES"
FONT_SRC="$ROOT/Sources/DiscleanApp/Resources/fonts"
if [ -d "$FONT_SRC" ]; then
    mkdir -p "$APP/Contents/Resources/fonts"
    cp "$FONT_SRC"/*.ttf "$APP/Contents/Resources/fonts/"
    # OFL は「配布物にライセンス文を同梱すること」を求めている
    cp "$FONT_SRC"/OFL-*.txt "$APP/Contents/Resources/LICENSES/" 2>/dev/null || true
fi

# ライセンス（同梱物のクレジット）を必ず入れる
mkdir -p "$APP/Contents/Resources/LICENSES"
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSES/"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

echo "==> built $APP"

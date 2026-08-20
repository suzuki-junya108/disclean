#!/bin/bash
# 配布物（CLI の tar.gz）を作る。
# 重要: SwiftPM のリソースバンドルを一緒に入れる。バイナリ単体では同梱ルールを読めない。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/DiscleanKit/Version.swift | head -1 | tr -d '"')"
BIN=".build/apple/Products/Release/disclean"
BUNDLE=".build/apple/Products/Release/Disclean_DiscleanKit.bundle"
[ -f "$BIN" ] || { echo "universal build が必要です: swift build -c release --arch arm64 --arch x86_64" >&2; exit 1; }
[ -d "$BUNDLE" ] || { echo "resource bundle が見つかりません: $BUNDLE" >&2; exit 1; }

rm -rf dist/pkg && mkdir -p dist/pkg
cp "$BIN" dist/pkg/
cp -R "$BUNDLE" dist/pkg/
cp LICENSE README.md dist/pkg/

TARBALL="dist/disclean-$VERSION-macos-universal.tar.gz"
tar -czf "$TARBALL" -C dist/pkg disclean Disclean_DiscleanKit.bundle LICENSE README.md

# 展開した状態で本当に動くかを、ここで必ず確かめる（バンドル同梱漏れの再発防止）
SMOKE="$(mktemp -d)"
tar -xzf "$TARBALL" -C "$SMOKE"
SB="$(mktemp -d)"
mkdir -p "$SB/Library/Caches"
if ! HOME="$SB" DISCLEAN_STATE_DIR="$SB/state" DISCLEAN_CONFIG_DIR="$SB/config" DISCLEAN_AUTO_UPDATE=0 \
    "$SMOKE/disclean" rules list --json | grep -q '"source" : "builtin"'; then
    echo "smoke test failed: 展開した配布物が同梱ルールを読めません" >&2
    rm -rf "$SMOKE" "$SB"
    exit 1
fi
rm -rf "$SMOKE" "$SB"

echo "==> $TARBALL"
shasum -a 256 "$TARBALL"

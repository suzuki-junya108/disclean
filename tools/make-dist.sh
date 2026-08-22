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
# 出力はいったんファイルに落とす。`grep -q` に直接つなぐと、ルールが増えて出力が
# パイプのバッファを超えたときに grep が先に閉じ、pipefail で誤って失敗扱いになる。
HOME="$SB" DISCLEAN_STATE_DIR="$SB/state" DISCLEAN_CONFIG_DIR="$SB/config" DISCLEAN_AUTO_UPDATE=0 \
    "$SMOKE/disclean" rules list --json > "$SB/rules.json" || true
if ! grep -q '"source" : "builtin"' "$SB/rules.json"; then
    echo "smoke test failed: 展開した配布物が同梱ルールを読めません" >&2
    rm -rf "$SMOKE" "$SB"
    exit 1
fi
rm -rf "$SMOKE" "$SB"

# 版に依存しない名前の複製も置く。LP や外部の案内は latest/download/<固定名> を指すため、
# これが無いとリリースのたびにダウンロードリンクが 404 になる（実際に壊れた）。
cp "$TARBALL" "dist/disclean-macos-universal.tar.gz"

echo "==> $TARBALL"
shasum -a 256 "$TARBALL"
echo "==> dist/disclean-macos-universal.tar.gz（固定名の複製）"

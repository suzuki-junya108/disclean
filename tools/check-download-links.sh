#!/bin/bash
# LP と README に書かれたダウンロードリンクが、本当に取得できるかを確かめる。
# リリース直後に必ず実行する（版数を含む固定リンクは、次のリリースで静かに 404 になる）。
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0

check() {
    local url="$1" label="$2"
    local code
    code="$(curl -sIL --max-time 30 -o /dev/null -w '%{http_code}' "$url")"
    if [ "$code" = "200" ]; then
        printf '  ok   %s\n' "$label"
    else
        printf '  FAIL %s → HTTP %s\n     %s\n' "$label" "$code" "$url"
        FAIL=$((FAIL + 1))
    fi
}

echo "== LP に書かれたリンク =="
grep -oE 'https://github\.com/[^"]+' site/index.html | sort -u | while read -r url; do
    case "$url" in
        *releases/latest/download/*) echo "$url" ;;
    esac
done > /tmp/disclean-links.txt
while read -r url; do
    [ -n "$url" ] && check "$url" "$(basename "$url")"
done < /tmp/disclean-links.txt
rm -f /tmp/disclean-links.txt

echo "== 更新の配信元 =="
for name in catalog-manifest.json catalog-manifest.json.sig; do
    check "https://github.com/suzuki-junya108/disclean/releases/latest/download/$name" "$name"
done

echo "== Homebrew tap =="
check "https://raw.githubusercontent.com/suzuki-junya108/homebrew-disclean/main/Formula/disclean.rb" "formula"

echo "== 公開 LP =="
check "https://disclean.i4u.jp/" "disclean.i4u.jp"

if [ "$FAIL" -eq 0 ]; then
    echo "すべて取得できました"
    exit 0
fi
echo "$FAIL 件のリンクが壊れています"
exit 1

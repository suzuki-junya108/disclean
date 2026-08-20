#!/bin/bash
# disclean.i4u.jp を GitHub Pages のカスタムドメインとして設定し、HTTPS 化まで確認する。
# 前提: Cloudflare に CNAME disclean -> suzuki-junya108.github.io（プロキシなし）が入っていること。
set -uo pipefail

DOMAIN="disclean.i4u.jp"
REPO="suzuki-junya108/disclean"
TARGET="suzuki-junya108.github.io"

step() { printf '\n==> %s\n' "$1"; }

step "DNS を確認する"
resolved="$(dig +short "$DOMAIN" @1.1.1.1 | head -3)"
if [ -z "$resolved" ]; then
    echo "まだ $DOMAIN が解決できません。Cloudflare に次の 1 本を追加してください:" >&2
    echo "  CNAME  disclean  ->  $TARGET  （プロキシ: DNS only / 灰色の雲）" >&2
    exit 1
fi
echo "$resolved"
if ! dig +short CNAME "$DOMAIN" @1.1.1.1 | grep -q "$TARGET"; then
    echo "注意: CNAME の先が $TARGET ではありません（プロキシ有効の可能性）。"
    echo "      その場合 GitHub は証明書を発行できません。DNS only に変更してください。"
fi

step "GitHub Pages にカスタムドメインを設定する"
gh api -X PUT "repos/$REPO/pages" -f "cname=$DOMAIN" -F "https_enforced=false" >/dev/null
gh api "repos/$REPO/pages" --jq '{cname, status, https_certificate: .https_certificate.state}'

step "証明書の発行を待つ（最大 15 分）"
for _ in $(seq 1 90); do
    state="$(gh api "repos/$REPO/pages" --jq '.https_certificate.state' 2>/dev/null || echo unknown)"
    [ "$state" = "approved" ] && break
    sleep 10
done
echo "certificate: ${state:-unknown}"

step "HTTPS を強制する"
gh api -X PUT "repos/$REPO/pages" -F "https_enforced=true" >/dev/null || \
    echo "（証明書がまだのため後で再実行してください: gh api -X PUT repos/$REPO/pages -F https_enforced=true）"

step "配信を確認する"
curl -sI "https://$DOMAIN/" | head -3
curl -s "https://$DOMAIN/" | grep -o '<title>.*</title>' | head -1
curl -sI "https://$DOMAIN/og.png" | head -1

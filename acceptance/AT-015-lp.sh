#!/bin/bash
# AT-015: 配布 LP の静的検査（F-16 / design-system D-02・D-03・D-08）
# ブラウザを使う検査（axe / 横スクロール / reduced-motion）は手動 QA（MQ-9〜MQ-11）で行う。
source "$(dirname "$0")/lib.sh"

SITE="$(cd "$(dirname "$0")/../site" && pwd)"
HTML="$SITE/index.html"

# --- 構成
for id in hero numbers safety hands-off install faq footer; do
    if grep -q "id=\"$id\"" "$HTML"; then ok "section #$id exists"; else ng "section #$id is missing"; fi
done

# --- 配布導線（LP からバイナリを配信しない: NG10）
assert_contains "brew コマンドを載せている" "brew install suzuki-junya108/disclean/disclean" "$(cat "$HTML")"
assert_contains ".dmg は GitHub Releases へのリンク" "github.com/suzuki-junya108/disclean/releases" "$(cat "$HTML")"
assert_eq "LP 自身がバイナリを持たない" "0" "$(find "$SITE" -name '*.dmg' -o -name '*.tar.gz' | wc -l | tr -d ' ')"

# --- デザインの禁則（D-02 / D-03）
if grep -rqE 'box-shadow:[^;]*[0-9]+px +[0-9]+px +[1-9]' "$SITE"; then
    ng "ぼかしのある影がある"
else
    ok "ぼかし影 0 件"
fi
if grep -rq 'linear-gradient\|radial-gradient' "$SITE"/*.css; then
    ng "グラデーションがある"
else
    ok "グラデーション 0 件"
fi

# --- 外部ホスト（D-08: Google Fonts のみ）
externals="$(grep -oE 'https://[a-z0-9.-]+' "$HTML" | sed 's|https://||' | sort -u \
    | grep -v -e 'github.com' -e 'disclean.i4u.jp' -e 'www.sitemaps.org' -e 'www.w3.org' || true)"
assert_eq "外部ホストは fonts の 2 つだけ" "fonts.googleapis.com
fonts.gstatic.com" "$externals"

# --- JS 無効でも読める（本文とインストール手順が HTML に直接ある）
assert_contains "JS なしでも見出しが読める" "そのギガバイト" "$(cat "$HTML")"
assert_contains "JS なしでも導入手順が読める" "1 行で入ります" "$(cat "$HTML")"

# --- 配信物
for f in CNAME robots.txt sitemap.xml og.png tokens.css style.css hero.js; do
    if [ -f "$SITE/$f" ]; then ok "$f がある"; else ng "$f がない"; fi
done
assert_eq "CNAME は独自ドメイン" "disclean.i4u.jp" "$(cat "$SITE/CNAME")"

# --- 公開文言と実装の整合（更新は通信する / 止められる）
assert_contains "通信する旨を書いている" "掃除ルールの更新を取りに行くときだけ" "$(cat "$HTML")"
assert_contains "止め方を書いている" "disclean update --off" "$(cat "$HTML")"

finish AT-015

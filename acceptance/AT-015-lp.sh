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

# --- ダウンロードリンクに版数を直書きしない（リリースのたびに 404 になるため）
versioned="$(grep -oE 'releases/latest/download/[^"]+' "$HTML" | grep -E '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [ -z "$versioned" ]; then
    ok "latest/download のリンクに版数が入っていない"
else
    ng "版数入りのリンクがある（次のリリースで 404 になります）: $versioned"
fi

# --- 配信物
for f in CNAME robots.txt sitemap.xml og.png tokens.css style.css hero.js; do
    if [ -f "$SITE/$f" ]; then ok "$f がある"; else ng "$f がない"; fi
done
assert_eq "CNAME は独自ドメイン" "disclean.i4u.jp" "$(cat "$SITE/CNAME")"

# --- 公開文言と実装の整合（更新は通信する / 止められる）
assert_contains "通信する旨を書いている" "掃除ルールの更新を取りに行くときだけ" "$(cat "$HTML")"
assert_contains "止め方を書いている" "disclean update --off" "$(cat "$HTML")"


# --- 特定の 1 台の Mac に依存した表示になっていないこと（F-LP）
assert_eq "no measured-machine claim in the hero" 0 \
    "$(grep -c 'MacBook（Apple M4' "$SITE/index.html" || true)"
assert_eq "no hard-coded measured sizes" 0 \
    "$(grep -cE '71\.5GB|26\.6GB|118<small>|実測 [0-9]' "$SITE/index.html" || true)"
assert_eq "the rule gallery is generated from the catalog" "true" \
    "$([ -f "$SITE/rules.js" ] && echo true || echo false)"
assert_eq "the generated data matches the shipped rules" "$(cat "$SITE/../Sources/DiscleanKit/Resources/rules"/*.json | grep -c '"id"')" \
    "$(python3 -c "import json,re,pathlib;s=pathlib.Path('$SITE/rules.js').read_text();print(json.loads(s[s.index('{'):-2])['totals']['rules'])")"

finish AT-015

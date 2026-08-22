#!/bin/bash
# AT-020: 場所をひな形（*）で書けること（F-01）。1 台の機械に縛られないルールのため。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

for dev in DEV-A DEV-B; do
    mkdir -p "$HOME/Library/Developer/CoreSimulator/Devices/$dev/data/Containers/Data/Application/APP-1/Library/Caches"
    dd if=/dev/zero of="$HOME/Library/Developer/CoreSimulator/Devices/$dev/data/Containers/Data/Application/APP-1/Library/Caches/model.bin" bs=1m count=2 2>/dev/null
done
# 隠しフォルダ（* では当たらない）と、外へ出るリンク（辿らない）
mkdir -p "$HOME/Library/Developer/CoreSimulator/Devices/.hidden/data/Containers/Data/Application/APP-1/Library/Caches"
OUTSIDE="$(mktemp -d)"
mkdir -p "$OUTSIDE/data/Containers/Data/Application/APP-1/Library/Caches"
dd if=/dev/zero of="$OUTSIDE/data/Containers/Data/Application/APP-1/Library/Caches/model.bin" bs=1m count=5 2>/dev/null
ln -s "$OUTSIDE" "$HOME/Library/Developer/CoreSimulator/Devices/ESCAPE"

cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-glob.json" <<'JSON'
[{"id":"glob-cache","title":"glob cache","tier":"A","kind":"directory",
  "paths":["~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Caches"],
  "whatIsLost":"rebuilt on next launch"}]
JSON

# 同梱ルールにも同じ形の対象があるため、この検証は対象を絞って行う。
out="$("$DISCLEAN_BIN" scan --json --rule glob-cache)"
assert_eq "matches every device id" 2 "$(echo "$out" | jq '[.items[] | select(.ruleId=="glob-cache")][0].paths | length')"
assert_eq "does not follow symlinks out of home" 0 \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="glob-cache")][0].paths | map(select(contains("ESCAPE"))) | length')"
assert_eq "does not match hidden entries" 0 \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="glob-cache")][0].paths | map(select(contains(".hidden"))) | length')"
assert_eq "counts both places" "true" \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="glob-cache")][0].bytes >= 4194304')"

# 見せた量と動かす量が一致し、戻せる
before="$(echo "$out" | jq '[.items[] | select(.ruleId=="glob-cache")][0].bytes')"
apply="$("$DISCLEAN_BIN" apply --rule glob-cache --yes --json)"
assert_eq "moves exactly what was shown" "$before" "$(echo "$apply" | jq '.totals.reclaimedBytes')"
assert_eq "quarantines both places" 2 "$(echo "$apply" | jq '.quarantined | length')"

undo="$("$DISCLEAN_BIN" undo --last --json)"
assert_eq "restores everything" "$before" "$(echo "$undo" | jq '.totals.bytes')"
assert_eq "the original place is back" "0" \
    "$([ -d "$HOME/Library/Developer/CoreSimulator/Devices/DEV-A/data/Containers/Data/Application/APP-1/Library/Caches" ] && echo 0 || echo 1)"

# リンクの先は一度も触られていない
assert_eq "leaves the outside tree alone" "0" \
    "$([ -f "$OUTSIDE/data/Containers/Data/Application/APP-1/Library/Caches/model.bin" ] && echo 0 || echo 1)"
rm -rf "$OUTSIDE"

# ひな形の固定部分が浅すぎるルールは拒否する
cat > "$DISCLEAN_CONFIG_DIR/rules.d/01-shallow.json" <<'JSON'
[{"id":"too-shallow","title":"shallow","tier":"A","kind":"directory",
  "paths":["~/*"],"whatIsLost":"everything"}]
JSON
out="$("$DISCLEAN_BIN" rules list 2>&1)"
assert_eq "rejects a pattern rooted too shallow" 0 \
    "$(echo "$out" | grep -c 'too-shallow' || true)"

finish AT-020

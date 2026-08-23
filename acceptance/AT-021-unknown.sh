#!/bin/bash
# AT-021: ルールが見ていない大きな場所を知らせる（F-21）。読み取りだけで、消さない。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

BASE="$HOME/Library/Application Support"
mkdir -p "$BASE/KnownApp" "$BASE/UnknownApp" "$BASE/TinyApp"
dd if=/dev/zero of="$BASE/KnownApp/a.bin" bs=1m count=6 2>/dev/null
dd if=/dev/zero of="$BASE/UnknownApp/b.bin" bs=1m count=8 2>/dev/null
dd if=/dev/zero of="$BASE/TinyApp/c.bin" bs=1m count=1 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-known.json" <<JSON
[{"id":"known-app","title":"known","tier":"A","kind":"directory",
  "paths":["$BASE/KnownApp"],"whatIsLost":"x"}]
JSON

out="$("$DISCLEAN_BIN" report --unknown --min-megabytes 4 --json)"
assert_eq "reports the unknown place" "true" \
    "$(echo "$out" | jq '[.places[].path | select(endswith("/UnknownApp"))] | length >= 1')"
assert_eq "does not report a place a rule already covers" "0" \
    "$(echo "$out" | jq '[.places[].path | select(endswith("/KnownApp"))] | length')"
assert_eq "does not report places below the threshold" "0" \
    "$(echo "$out" | jq '[.places[].path | select(endswith("/TinyApp"))] | length')"
assert_eq "never reports its own quarantine" "0" \
    "$(echo "$out" | jq --arg s "$DISCLEAN_STATE_DIR" '[.places[].path | select(startswith($s))] | length')"

# 読むだけ。何も消えない
assert_eq "leaves every file in place" "3" \
    "$(ls "$BASE"/*/*.bin | wc -l | tr -d ' ')"

# 人向け表示にも出る
human="$("$DISCLEAN_BIN" report --unknown --min-megabytes 4 2>&1)"
assert_contains "explains that nothing is deleted" "never deleted" "$human"
assert_contains "points at how to look inside" "disclean inspect --path" "$human"

finish AT-021

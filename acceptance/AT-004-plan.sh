#!/bin/bash
# AT-004: 既定選択と Tier C の選択不可（F-04）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

mkdir -p "$HOME/Library/Caches/fa" "$HOME/Library/Caches/fb"
dd if=/dev/zero of="$HOME/Library/Caches/fa/a.bin" bs=1m count=1 2>/dev/null
dd if=/dev/zero of="$HOME/Library/Caches/fb/b.bin" bs=1m count=1 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-fixtures.json" <<JSON
[{"id":"fixture-a","title":"a","tier":"A","kind":"directory","paths":["$HOME/Library/Caches/fa"],"whatIsLost":"x"},
 {"id":"fixture-b","title":"b","tier":"B","kind":"directory","paths":["$HOME/Library/Caches/fb"],"whatIsLost":"x"}]
JSON

out="$("$DISCLEAN_BIN" plan --json)"
assert_eq "plan selects only tier A" "true" "$(echo "$out" | jq '[.selected[].ruleId] | index("fixture-a") != null and (index("fixture-b") == null)')"

out="$("$DISCLEAN_BIN" plan --select trash 2>&1)"; code=$?
assert_eq "tier C selection exits 2" 2 "$code"
assert_contains "explains tier C" "tier C rules cannot be selected" "$out"

out="$("$DISCLEAN_BIN" plan --select does-not-exist 2>&1)"; code=$?
assert_eq "unknown rule id exits 2" 2 "$code"
assert_contains "names the unknown rule" "unknown rule id" "$out"
finish AT-004

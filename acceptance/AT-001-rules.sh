#!/bin/bash
# AT-001: ルールカタログの読込と検証（F-01）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

out="$("$DISCLEAN_BIN" rules list --json)"
assert_eq "rules list exits 0" 0 $?
assert_eq "all builtin rules load" "true" "$(echo "$out" | jq '[.rules[].source] | all(. == "builtin")')"
assert_eq "catalog is not empty" "true" "$(echo "$out" | jq '(.rules | length) >= 1')"
assert_eq "valid: true" "true" "$(echo "$out" | jq '.valid')"

cat > "$DISCLEAN_CONFIG_DIR/rules.d/99-bad.json" <<'JSON'
[{"id":"evil","title":"evil","tier":"A","kind":"directory","paths":["/"],"whatIsLost":"everything"}]
JSON
out="$("$DISCLEAN_BIN" rules validate --json)"; code=$?
assert_eq "forbidden path rejected with exit 5" 5 "$code"
assert_contains "reports forbidden path" "forbidden path" "$out"
assert_eq "evil rule is not in the catalog" "0" "$("$DISCLEAN_BIN" rules list --json | jq '[.rules[] | select(.id == "evil")] | length')"

finish AT-001

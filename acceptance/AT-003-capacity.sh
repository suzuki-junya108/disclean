#!/bin/bash
# AT-003: 容量計測と回収量の帰属（F-03）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

out="$("$DISCLEAN_BIN" scan --json)"
assert_eq "strictBytes > 0" "true" "$(echo "$out" | jq '.capacity.strictBytes > 0')"
assert_eq "importantBytes >= strictBytes" "true" \
    "$(echo "$out" | jq '.capacity.importantBytes >= .capacity.strictBytes')"

FIXTURE="$HOME/Library/Caches/fixture"; mkdir -p "$FIXTURE"
dd if=/dev/zero of="$FIXTURE/a.bin" bs=1m count=2 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-test-fixture.json" <<JSON
[{"id":"test-fixture","title":"fixture","tier":"A","kind":"directory","paths":["$FIXTURE"],"whatIsLost":"test"}]
JSON
out="$("$DISCLEAN_BIN" apply --rule test-fixture --yes --json)"
assert_eq "reclaimedBytes is reported" "true" "$(echo "$out" | jq '.totals.reclaimedBytes > 0')"
assert_eq "freeSpaceDeltaBytes is separate" "true" "$(echo "$out" | jq 'has("capacity") and (.capacity | has("freeSpaceDeltaBytes"))')"
finish AT-003

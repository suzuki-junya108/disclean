#!/bin/bash
# AT-007: 監査ログと履歴（F-08）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

FIXTURE="$HOME/Library/Caches/fixture"; mkdir -p "$FIXTURE"
for i in 1 2; do dd if=/dev/zero of="$FIXTURE/f$i.bin" bs=1m count=1 2>/dev/null; done
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-test-fixture.json" <<JSON
[{"id":"test-fixture","title":"fixture","tier":"A","kind":"directory","paths":["$FIXTURE"],"whatIsLost":"test"}]
JSON

"$DISCLEAN_BIN" apply --rule test-fixture --yes --json > /dev/null
out="$("$DISCLEAN_BIN" history --json)"
assert_eq "apply is recorded per item" "2" "$(echo "$out" | jq '[.records[] | select(.action=="apply")] | length')"
assert_eq "records carry ts/runId/path/bytes" "true" \
    "$(echo "$out" | jq '[.records[] | select(.action=="apply")] | all(has("ts") and has("runId") and has("path") and has("bytes"))')"
assert_eq "records carry the OS build" "true" "$(echo "$out" | jq '[.records[].osBuild] | all(. != "")')"

# 監査ログに書けないときは 1 件も消さない
for i in 3 4; do dd if=/dev/zero of="$FIXTURE/f$i.bin" bs=1m count=1 2>/dev/null; done
chmod 500 "$DISCLEAN_STATE_DIR/audit"
out="$("$DISCLEAN_BIN" apply --rule test-fixture --yes 2>&1)"; code=$?
chmod 700 "$DISCLEAN_STATE_DIR/audit"
assert_eq "apply fails with exit 1" 1 "$code"
assert_contains "explains the audit failure" "audit: cannot write log" "$out"
assert_eq "no file was removed" "2" "$(find "$FIXTURE" -type f | wc -l | tr -d ' ')"
finish AT-007

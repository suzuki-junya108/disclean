#!/bin/bash
# AT-002: スキャンは読み取り専用・キャッシュが効く（F-02, WS-k）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

FIXTURE="$HOME/Library/Caches/fixture"
mkdir -p "$FIXTURE"
for i in 1 2 3; do dd if=/dev/zero of="$FIXTURE/file-$i.bin" bs=1m count=1 2>/dev/null; done
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-test-fixture.json" <<JSON
[{"id":"test-fixture","title":"fixture","tier":"A","kind":"directory",
  "paths":["$FIXTURE"],"whatIsLost":"test data"}]
JSON

out="$("$DISCLEAN_BIN" scan --rule test-fixture --json)"; code=$?
assert_eq "scan exits 0" 0 "$code"
bytes="$(echo "$out" | jq '[.items[] | select(.ruleId=="test-fixture") | .bytes] | first // 0')"
assert_eq "measures ~3MiB" "true" "$([ "$bytes" -ge 3145728 ] && [ "$bytes" -le 3670016 ] && echo true || echo false)"
assert_eq "state is ready" "ready" "$(echo "$out" | jq -r '.items[] | select(.ruleId=="test-fixture") | .state')"

out2="$("$DISCLEAN_BIN" scan --rule test-fixture --json)"
assert_eq "second scan is a cache hit" "true" "$(echo "$out2" | jq '.items[] | select(.ruleId=="test-fixture") | .cacheHit')"

# WS-k: スキャンは隔離庫に書き込まない
assert_eq "quarantine stays empty" "0" "$(find "$DISCLEAN_STATE_DIR/quarantine" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "fixture files untouched" "3" "$(find "$FIXTURE" -type f | wc -l | tr -d ' ')"

finish AT-002

#!/bin/bash
# AT-005: 隔離と復元、安全ガード、非対話での --yes 必須（F-05, F-07）
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

# AC3: 非対話では --yes が必須
out="$("$DISCLEAN_BIN" apply --rule test-fixture < /dev/null 2>&1)"; code=$?
assert_eq "non-interactive apply without --yes exits 2" 2 "$code"
assert_contains "explains --yes requirement" "--yes is required" "$out"
assert_eq "nothing was moved" "3" "$(find "$FIXTURE" -type f | wc -l | tr -d ' ')"

# AC1: 隔離
out="$("$DISCLEAN_BIN" apply --rule test-fixture --yes --json)"; code=$?
assert_eq "apply exits 0" 0 "$code"
assert_eq "3 items quarantined" "3" "$(echo "$out" | jq '.quarantined | length')"
assert_eq "original files are gone" "0" "$(find "$FIXTURE" -type f | wc -l | tr -d ' ')"
run_id="$(echo "$out" | jq -r '.runId')"
assert_eq "quarantine holds 3 files" "3" "$(find "$DISCLEAN_STATE_DIR/quarantine/$run_id" -type f | wc -l | tr -d ' ')"
before_bytes="$(echo "$out" | jq '.totals.reclaimedBytes')"

# AC1: 復元
out="$("$DISCLEAN_BIN" undo --last --json)"; code=$?
assert_eq "undo exits 0" 0 "$code"
assert_eq "3 items restored" "3" "$(echo "$out" | jq '.restored | length')"
assert_eq "restored bytes match" "$before_bytes" "$(echo "$out" | jq '.totals.bytes')"
assert_eq "files are back" "3" "$(find "$FIXTURE" -type f | wc -l | tr -d ' ')"

# AC2: 浅すぎるパスは隔離しない
cat > "$DISCLEAN_CONFIG_DIR/rules.d/01-shallow.json" <<JSON
[{"id":"shallow-test","title":"shallow","tier":"A","kind":"directory",
  "paths":["~/Library"],"whatIsLost":"everything"}]
JSON
out="$("$DISCLEAN_BIN" rules list --json | jq '[.rules[] | select(.id=="shallow-test")] | length')"
assert_eq "too-shallow rule is rejected by the catalog" "0" "$out"

# --- 表示した量と、実際に移した量が一致すること（入れ子のディレクトリ）
NESTED="$HOME/Library/Caches/nested"
mkdir -p "$NESTED/a/sub" "$NESTED/b/sub"
dd if=/dev/zero of="$NESTED/a/sub/data.bin" bs=1m count=6 2>/dev/null
dd if=/dev/zero of="$NESTED/b/sub/data.bin" bs=1m count=6 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/02-nested.json" <<JSON
[{"id":"nested","title":"nested","tier":"A","kind":"directory","paths":["$NESTED"],"whatIsLost":"x"}]
JSON
shown="$("$DISCLEAN_BIN" scan --rule nested --json | jq '.totals.bytes')"
moved="$("$DISCLEAN_BIN" apply --rule nested --yes --json | jq '.totals.reclaimedBytes')"
assert_eq "表示した量と移した量が一致する" "$shown" "$moved"
assert_eq "入れ子でも 0 にならない" "true" "$([ "$moved" -ge 12582912 ] && echo true || echo false)"

# --- 条件つきルールは、絞った後の量を見せること
AGED="$HOME/Library/Caches/aged"
mkdir -p "$AGED/old" "$AGED/new"
dd if=/dev/zero of="$AGED/old/a.bin" bs=1m count=8 2>/dev/null
dd if=/dev/zero of="$AGED/new/b.bin" bs=1m count=8 2>/dev/null
touch -t 202501010000 "$AGED/old/a.bin" "$AGED/old"
cat > "$DISCLEAN_CONFIG_DIR/rules.d/03-aged.json" <<JSON
[{"id":"aged","title":"aged","tier":"A","kind":"directory","paths":["$AGED"],
  "minAgeDays":3,"whatIsLost":"x"}]
JSON
shown="$("$DISCLEAN_BIN" scan --rule aged --json | jq '.totals.bytes')"
moved="$("$DISCLEAN_BIN" apply --rule aged --yes --json | jq '.totals.reclaimedBytes')"
assert_eq "条件つきでも表示と実際が一致する" "$shown" "$moved"
assert_eq "新しいものは残る" "1" "$(ls "$AGED/new" | wc -l | tr -d ' ')"

finish AT-005

#!/bin/bash
# AT-006: TTL 満了の自動削除と明示 purge（F-06）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

FIXTURE="$HOME/Library/Caches/fixture"; mkdir -p "$FIXTURE"
dd if=/dev/zero of="$FIXTURE/a.bin" bs=1m count=1 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-test-fixture.json" <<JSON
[{"id":"test-fixture","title":"fixture","tier":"A","kind":"directory","paths":["$FIXTURE"],"whatIsLost":"test"}]
JSON

DISCLEAN_QUARANTINE_TTL_DAYS=1 "$DISCLEAN_BIN" apply --rule test-fixture --yes --json > /dev/null
out="$("$DISCLEAN_BIN" purge --json)"
assert_eq "unexpired runs are kept" "0" "$(echo "$out" | jq '.purged | length')"
assert_eq "quarantine still has the run" "1" "$(jq '.runs | length' "$DISCLEAN_STATE_DIR/quarantine/index.json")"

out="$("$DISCLEAN_BIN" purge --all --force --json)"
assert_eq "purge --all removes it" "1" "$(echo "$out" | jq '.purged | length')"
assert_eq "index is empty" "0" "$(jq '.runs | length' "$DISCLEAN_STATE_DIR/quarantine/index.json")"

dd if=/dev/zero of="$FIXTURE/b.bin" bs=1m count=1 2>/dev/null
DISCLEAN_QUARANTINE_TTL_DAYS=1 "$DISCLEAN_BIN" apply --rule test-fixture --yes --json > /dev/null
# 失効済みに書き換えると、次回起動時に自動で消える
python3 - "$DISCLEAN_STATE_DIR/quarantine/index.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
for run in data["runs"]:
    run["expiresAt"] = "2000-01-01T00:00:00.000+00:00"
json.dump(data, open(p, "w"))
PY
out="$("$DISCLEAN_BIN" purge --json)"
assert_eq "expired run is purged on next start" "1" "$(echo "$out" | jq '.purged | length')"
finish AT-006

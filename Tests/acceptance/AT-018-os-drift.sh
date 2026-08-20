#!/bin/bash
# AT-018: OS 変化の検知と OS 条件の評価（F-19）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

"$DISCLEAN_BIN" doctor --json > /dev/null   # env.json を作る
python3 - "$DISCLEAN_STATE_DIR/env.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["osBuild"] = "00A00"
json.dump(data, open(p, "w"))
PY
out="$("$DISCLEAN_BIN" doctor --json)"
assert_eq "detects the OS change" "00A00" "$(echo "$out" | jq -r '.os.changedSince')"
assert_eq "scan cache is cleared" "0" \
    "$(jq '.entries | length' "$DISCLEAN_STATE_DIR/cache/scan-cache.json" 2>/dev/null || echo 0)"

mkdir -p "$HOME/Library/Caches/future"
dd if=/dev/zero of="$HOME/Library/Caches/future/a.bin" bs=1m count=1 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-future.json" <<JSON
[{"id":"future-rule","title":"future","tier":"A","kind":"directory",
  "paths":["$HOME/Library/Caches/future"],"whatIsLost":"x","minMacOS":"99.0"}]
JSON
out="$("$DISCLEAN_BIN" scan --json)"
assert_eq "rule for a future OS is not a target" "0" \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="future-rule")] | length')"
assert_eq "doctor lists it as disabled by OS" "true" \
    "$("$DISCLEAN_BIN" doctor --json | jq '[.os.rulesDisabledByOS[] | select(.ruleId=="future-rule")] | length >= 1')"
finish AT-018

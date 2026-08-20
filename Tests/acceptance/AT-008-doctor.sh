#!/bin/bash
# AT-008: 環境診断（F-09）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

out="$("$DISCLEAN_BIN" doctor --json)"; code=$?
assert_eq "doctor exits 0 or 3" "true" "$([ "$code" = 0 ] || [ "$code" = 3 ] && echo true || echo false)"
assert_eq "fullDiskAccess is a boolean" "true" "$(echo "$out" | jq '.fullDiskAccess | type == "boolean"')"
assert_eq "tools are listed" "true" "$(echo "$out" | jq '(.tools | length) >= 1')"
assert_eq "stateDir is absolute" "true" "$(echo "$out" | jq '.state.stateDir | startswith("/")')"
assert_eq "os build is reported" "true" "$(echo "$out" | jq '.os.build != ""')"

rm -rf "$DISCLEAN_STATE_DIR"
"$DISCLEAN_BIN" doctor --initialize --json > /dev/null
for dir in quarantine audit cache updates; do
    assert_eq "creates $dir" "true" "$([ -d "$DISCLEAN_STATE_DIR/$dir" ] && echo true || echo false)"
done
assert_eq "state dirs are 0700" "700" "$(stat -f "%OLp" "$DISCLEAN_STATE_DIR/quarantine")"
finish AT-008

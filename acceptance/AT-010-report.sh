#!/bin/bash
# AT-010: Tier C は表示のみ（F-11）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

out="$("$DISCLEAN_BIN" report --json)"; code=$?
assert_eq "report exits 0 or 3" "true" "$([ "$code" = 0 ] || [ "$code" = 3 ] && echo true || echo false)"
assert_eq "every item explains what is lost" "true" "$(echo "$out" | jq '[.items[] | .whatIsLost != ""] | all')"
assert_eq "every item has manual steps" "true" "$(echo "$out" | jq '[.items[] | .manualSteps != null] | all')"
assert_eq "tier C never appears as a target" "0" "$("$DISCLEAN_BIN" plan --json | jq '[.selected[] | select(.ruleId=="trash")] | length')"

out="$("$DISCLEAN_BIN" apply --tier C --yes 2>&1)"; code=$?
assert_eq "apply --tier C exits 2" 2 "$code"
assert_contains "explains tier C" "tier C rules cannot be selected" "$out"
finish AT-010

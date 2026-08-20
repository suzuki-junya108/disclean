#!/bin/bash
# AT-009: command 型ルールの実行・スキップ・タイムアウト（F-10）
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-command.json" <<'JSON'
[{"id":"echo-test","title":"echo","tier":"A","kind":"command",
  "command":{"executable":"/bin/echo","arguments":["hello"]},"whatIsLost":"nothing"},
 {"id":"missing-tool","title":"missing","tier":"A","kind":"command",
  "detect":{"executable":"/nonexistent/tool","arguments":["--version"]},
  "command":{"executable":"/nonexistent/tool","arguments":["clean"]},"whatIsLost":"nothing"},
 {"id":"slow-test","title":"slow","tier":"A","kind":"command",
  "command":{"executable":"/bin/sleep","arguments":["30"]},"timeoutSeconds":1,"whatIsLost":"nothing"}]
JSON

out="$("$DISCLEAN_BIN" apply --rule echo-test --yes --json)"
assert_eq "command rule runs" "1" "$(echo "$out" | jq '.commands | length')"

out="$("$DISCLEAN_BIN" scan --rule missing-tool --json)"
assert_eq "missing tool is skipped, not failed" "tool-not-found" \
    "$(echo "$out" | jq -r '.items[] | select(.ruleId=="missing-tool") | .reason')"

out="$("$DISCLEAN_BIN" apply --rule slow-test --yes --json)"; code=$?
assert_eq "timeout exits 4" 4 "$code"
assert_contains "reports the timeout" "timeout" "$(echo "$out" | jq -r '.failed[0].error')"
sleep 1
assert_eq "no sleep process is left behind" "0" "$(pgrep -f '^/bin/sleep 30$' | wc -l | tr -d ' ')"
finish AT-009

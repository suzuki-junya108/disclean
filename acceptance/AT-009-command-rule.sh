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
# --- 実行前に量が分かること / 実行後に実際に空けた量が出ること
FAKE="$HOME/fakecache"; mkdir -p "$FAKE"
for i in 1 2 3; do dd if=/dev/zero of="$FAKE/f$i.bin" bs=1m count=4 2>/dev/null; done
cat > "$DISCLEAN_CONFIG_DIR/rules.d/01-measured.json" <<JSON
[{"id":"measured-cache","title":"measured","tier":"A","kind":"command",
  "command":{"executable":"/bin/rm","arguments":["-rf","$FAKE"]},
  "measure":{"kind":"paths","paths":["$FAKE"]},
  "whatIsLost":"cache"}]
JSON
out="$("$DISCLEAN_BIN" scan --rule measured-cache --json)"
assert_eq "実行前に量が分かる" "true" "$(echo "$out" | jq '[.items[] | select(.ruleId=="measured-cache")] | .[0].sizeKnown')"
assert_eq "見積もりが実サイズに一致する" "true" \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="measured-cache")] | .[0].bytes >= 12582912')"

out="$("$DISCLEAN_BIN" apply --rule measured-cache --yes --json)"
assert_eq "実際に空けた量を報告する" "true" \
    "$(echo "$out" | jq '[.commands[] | select(.ruleId=="measured-cache")] | .[0].reclaimedBytes >= 12582912')"
assert_eq "合計にも含まれる" "true" "$(echo "$out" | jq '.totals.reclaimedBytes >= 12582912')"
assert_eq "対象が消えている" "0" "$(ls "$FAKE" 2>/dev/null | wc -l | tr -d ' ')"

# --- 測れないルールは「不明」であって 0 ではない
out="$("$DISCLEAN_BIN" scan --rule echo-test --json)"
assert_eq "測れないルールは不明として出る" "false" \
    "$(echo "$out" | jq '[.items[] | select(.ruleId=="echo-test")] | .[0].sizeKnown')"

# --- 空の対象は実行せずスキップする
cat > "$DISCLEAN_CONFIG_DIR/rules.d/02-empty.json" <<JSON
[{"id":"empty-cache","title":"empty","tier":"A","kind":"command",
  "command":{"executable":"/bin/echo","arguments":["nothing"]},
  "measure":{"kind":"paths","paths":["$HOME/no-such-dir"]},
  "whatIsLost":"nothing"}]
JSON
out="$("$DISCLEAN_BIN" scan --rule empty-cache --json)"
assert_eq "空の対象はスキップ" "empty" "$(echo "$out" | jq -r '[.items[] | select(.ruleId=="empty-cache")] | .[0].reason')"

# --- 表示に "Zero" を出さない
text="$("$DISCLEAN_BIN" apply --rule empty-cache --yes 2>&1)"
case "$text" in
    *Zero*) ng "0 バイトが Zero と表示される" ;;
    *) ok "Zero 表記が出ない" ;;
esac

finish AT-009

#!/bin/bash
# AT-024: システムデータの中身を見せる（F-23）。読むだけで、何も消さない・書かない。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

mkdir -p "$HOME/Library/Application Support/FileProvider/x"
dd if=/dev/zero of="$HOME/Library/Application Support/FileProvider/x/blob" bs=1m count=3 2>/dev/null
before="$(find "$SANDBOX" -print | sort)"

out="$("$DISCLEAN_BIN" report --system --json)"; code=$?
assert_eq "exits 0" 0 "$code"
assert_eq "mode is system" "system" "$(echo "$out" | jq -r '.mode')"
assert_eq "lists all eight kinds" "8" "$(echo "$out" | jq '.items | length')"
assert_eq "every item says why it is not deleted" "0" \
    "$(echo "$out" | jq '[.items[] | select((.whyNotDeleted | length) == 0 or (.howToReduce | length) == 0)] | length')"
assert_eq "unknown sizes are null, never 0" "0" \
    "$(echo "$out" | jq '[.items[] | select((.state=="blocked" or .state=="unknown") and .bytes != null)] | length')"
assert_eq "measures the sync staging in home" "true" \
    "$(echo "$out" | jq '.items[] | select(.id=="file-provider") | .bytes >= 3145728')"
for id in simulator-runtimes swap sleep-image software-updates system-logs file-provider user-temporary purgeable; do
    assert_eq "has $id" "1" "$(echo "$out" | jq --arg id "$id" '[.items[] | select(.id==$id)] | length')"
done

human="$("$DISCLEAN_BIN" report --system 2>&1)"
assert_contains "explains nothing is deleted" "never deletes" "$human"
assert_contains "shows the reason for each" "why not deleted:" "$human"
assert_contains "points to what disclean can clean" "simulator runtimes" "$human"

"$DISCLEAN_BIN" report --system --unknown >/dev/null 2>&1; code=$?
assert_eq "--system and --unknown together is an argument error" 2 "$code"

# 読むだけ。サンドボックスの中で増えた・消えたものが無い（状態ディレクトリへの書き込みも無い）
after="$(find "$SANDBOX" -print | sort)"
assert_eq "writes and deletes nothing" "$before" "$after"

finish AT-024

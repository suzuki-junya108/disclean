#!/bin/bash
# AT-019: なかみを見る（F-19）。ファイル単位で、何がどれだけ入っているかを読み取りだけで出す。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

mkdir -p "$HOME/Library/Caches/fixture/packages"
dd if=/dev/zero of="$HOME/Library/Caches/fixture/packages/big.tgz" bs=1m count=3 2>/dev/null
dd if=/dev/zero of="$HOME/Library/Caches/fixture/install.log" bs=1m count=1 2>/dev/null
cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-fixtures.json" <<JSON
[{"id":"fixture-a","title":"fixture cache","tier":"A","kind":"directory",
  "paths":["$HOME/Library/Caches/fixture"],"whatIsLost":"rebuilt on next use"}]
JSON

out="$("$DISCLEAN_BIN" inspect fixture-a --json)"
assert_eq "reports the rule as the target" "rule" "$(echo "$out" | jq -r '.target.kind')"
assert_eq "says it is undoable" "true" "$(echo "$out" | jq -r '.target.undoable')"
assert_eq "lists the biggest entry first" "packages" "$(echo "$out" | jq -r '.entries[0].name')"
assert_eq "names the kind of each file" "log" \
    "$(echo "$out" | jq -r '.entries[] | select(.name=="install.log") | .kind')"
assert_eq "counts files inside folders" "1" \
    "$(echo "$out" | jq -r '.entries[] | select(.name=="packages") | .fileCount')"
assert_eq "totals every file" "2" "$(echo "$out" | jq -r '.totals.fileCount')"

# 読み取りだけ。中身は動かない。
assert_eq "leaves the files in place" "1" \
    "$(ls "$HOME/Library/Caches/fixture/packages" | wc -l | tr -d ' ')"

# 1 段下がって見る
out="$("$DISCLEAN_BIN" inspect --path "$HOME/Library/Caches/fixture/packages" --json)"
assert_eq "opens a folder one level down" "big.tgz" "$(echo "$out" | jq -r '.entries[0].name')"
assert_eq "recognises archives" "archive" "$(echo "$out" | jq -r '.entries[0].kind')"

# ホームの外は見せない
out="$("$DISCLEAN_BIN" inspect --path /System/Library 2>&1)"; code=$?
assert_eq "refuses paths outside home" 2 "$code"
assert_contains "explains the refusal" "inside your home directory" "$out"

# 隔離したあとも、何が入っているかを見られる
"$DISCLEAN_BIN" apply --tier A --yes >/dev/null 2>&1
run_id="$("$DISCLEAN_BIN" history --json | jq -r '[.records[] | select(.action=="apply")][0].runId')"
out="$("$DISCLEAN_BIN" inspect --run "$run_id" --json)"
assert_eq "reports the run as the target" "run" "$(echo "$out" | jq -r '.target.kind')"
assert_contains "keeps the original path" "Library/Caches/fixture" "$(echo "$out" | jq -r '.items[0].originalPath')"
assert_eq "still lists the files inside" "big.tgz" \
    "$(echo "$out" | jq -r '[.items[].entries[] | select(.name=="big.tgz")][0].name')"

finish AT-019

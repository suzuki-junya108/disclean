#!/bin/bash
# AT-022: 書類の中の大きいものを探し、選んだものだけを隔離庫へ移す。
# 探すだけでは何も動かないこと、部品置き場が 1 件にまとまること、undo で戻ることを見る。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

mkdir -p "$HOME/Movies" "$HOME/Documents/proj/node_modules/pkg" "$HOME/Documents/Big.app/Contents"
dd if=/dev/zero of="$HOME/Movies/holiday.mov" bs=1m count=12 2>/dev/null
dd if=/dev/zero of="$HOME/Documents/proj/node_modules/pkg/a.bin" bs=1m count=9 2>/dev/null
dd if=/dev/zero of="$HOME/Documents/Big.app/Contents/binary" bs=1m count=7 2>/dev/null
dd if=/dev/zero of="$HOME/Documents/small.bin" bs=1m count=1 2>/dev/null
dd if=/dev/zero of="$HOME/toplevel.bin" bs=1m count=8 2>/dev/null

out="$("$DISCLEAN_BIN" big --min-megabytes 5 --json)"
assert_eq "finds the plain file" "1" \
    "$(echo "$out" | jq '[.items[] | select(.path | endswith("/Movies/holiday.mov"))] | length')"
assert_eq "groups a dependency store into one item" "parts" \
    "$(echo "$out" | jq -r '.items[] | select(.path | endswith("/node_modules")) | .group')"
assert_eq "never lists files inside the dependency store" "0" \
    "$(echo "$out" | jq '[.items[].path | select(contains("node_modules/"))] | length')"
assert_eq "groups a bundle into one item" "bundle" \
    "$(echo "$out" | jq -r '.items[] | select(.path | endswith("/Big.app")) | .group')"
assert_eq "leaves out things below the threshold" "0" \
    "$(echo "$out" | jq '[.items[].path | select(endswith("small.bin"))] | length')"
assert_eq "leaves out files sitting directly in home" "0" \
    "$(echo "$out" | jq '[.items[].path | select(endswith("toplevel.bin"))] | length')"
assert_eq "says how much it looked at" "true" \
    "$(echo "$out" | jq '.totals.scannedEntries > 0')"

# 探すだけでは何も動かない
assert_eq "searching moves nothing" "4" \
    "$(find "$HOME/Movies" "$HOME/Documents" -type f | wc -l | tr -d ' ')"

# 人向け表示にも「消さない」と出る
human="$("$DISCLEAN_BIN" big --min-megabytes 5 2>&1)"
assert_contains "says nothing is deleted here" "never deleted here" "$human"
assert_contains "points at how to move one" "disclean big --move" "$human"

# 選んだものだけを移す
moved="$("$DISCLEAN_BIN" big --move "$HOME/Movies/holiday.mov" --yes --json)"
assert_eq "moves the chosen item" "1" "$(echo "$moved" | jq '.quarantined | length')"
assert_eq "the chosen item leaves its place" "0" \
    "$(ls "$HOME/Movies" | wc -l | tr -d ' ')"
assert_eq "everything else stays" "1" \
    "$(ls "$HOME/Documents/Big.app/Contents" | wc -l | tr -d ' ')"

# 戻せる
"$DISCLEAN_BIN" undo --last >/dev/null 2>&1
assert_eq "undo puts it back" "1" "$(ls "$HOME/Movies" | wc -l | tr -d ' ')"

# ホーム直下は移せない（安全ガードの範囲外）。理由を付けて見送る
shallow="$("$DISCLEAN_BIN" big --move "$HOME/toplevel.bin" --yes --json)"
assert_eq "refuses a target that is too shallow" "too-shallow" \
    "$(echo "$shallow" | jq -r '.skipped[0].reason')"
assert_eq "the refused file is still there" "0" "$([ -f "$HOME/toplevel.bin" ]; echo $?)"

# 対話でないときに --yes を省いたら止まる
"$DISCLEAN_BIN" big --move "$HOME/Movies/holiday.mov" </dev/null >/dev/null 2>&1
assert_eq "requires --yes when not interactive" "2" "$?"

finish AT-022

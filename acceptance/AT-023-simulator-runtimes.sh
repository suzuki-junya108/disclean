#!/bin/bash
# AT-023: シミュレータ本体を simctl 経由で片づける（F-22）。
# 本物の simctl の代わりに、同じ引数に同じ形で答える台本を一時ディレクトリに置く。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap teardown_sandbox EXIT

FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/images" "$FAKE/dyld/25F84"
cat > "$FAKE/xcrun" <<'SH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$1 $2 $3" = "simctl runtime list" ]; then
  printf '{'; first=1
  for f in "$DIR"/images/*.json; do
    [ -e "$f" ] || continue
    [ "$first" = 1 ] || printf ','
    cat "$f"; first=0
  done
  printf '}\n'; exit 0
fi
if [ "$1 $2 $3" = "simctl runtime delete" ]; then
  dry=0
  for a in "$@"; do [ "$a" = "--dry-run" ] && dry=1; done
  [ -f "$DIR/targets.txt" ] || exit 0
  while read -r id; do
    [ -n "$id" ] || continue
    [ -e "$DIR/images/$id.json" ] || continue
    if [ "$dry" = 1 ]; then
      echo "Would delete P: $id iOS (Ready)"
    else
      rm -f "$DIR/images/$id.json"
      rm -rf "$DIR"/dyld/*/"com.apple.CoreSimulator.SimRuntime.iOS-26-1.23B5059e"
    fi
  done < "$DIR/targets.txt"
  exit 0
fi
if [ "$1 $2" = "simctl list" ]; then
  echo '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-1","buildversion":"23B86"}],"devices":{}}'
  exit 0
fi
exit 1
SH
chmod +x "$FAKE/xcrun"

BETA=70224A2C-559D-4C8B-83A3-DD2B8060185C
RELEASE=00E5C5F8-59D9-4AE7-9DB5-3B691935C812
cat > "$FAKE/images/$BETA.json" <<JSON
"$BETA": {"identifier":"$BETA","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-1","version":"26.1","build":"23B5059e","sizeBytes":6000000,"lastUsedAt":"2025-10-27T09:37:24Z"}
JSON
cat > "$FAKE/images/$RELEASE.json" <<JSON
"$RELEASE": {"identifier":"$RELEASE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-1","version":"26.1","build":"23B86","sizeBytes":9000000,"lastUsedAt":"2026-08-06T11:22:27Z"}
JSON
echo "$BETA" > "$FAKE/targets.txt"
mkdir -p "$FAKE/dyld/25F84/com.apple.CoreSimulator.SimRuntime.iOS-26-1.23B5059e"
dd if=/dev/zero of="$FAKE/dyld/25F84/com.apple.CoreSimulator.SimRuntime.iOS-26-1.23B5059e/cache" bs=1m count=4 2>/dev/null

cat > "$DISCLEAN_CONFIG_DIR/rules.d/00-runtimes.json" <<JSON
[{"id":"fake-runtimes","title":"old runtimes","tier":"A","kind":"command",
  "command":{"executable":"$FAKE/xcrun","arguments":["simctl","runtime","delete","--outdated"]},
  "measure":{"kind":"simctlRuntimes",
    "command":{"executable":"$FAKE/xcrun","arguments":["simctl","runtime","delete","--outdated","--dry-run"]},
    "paths":["$FAKE/dyld"]},
  "whatIsLost":"old runtime"}]
JSON

# --- 同梱ルールに入っている
rules="$("$DISCLEAN_BIN" rules list --json)"
assert_eq "outdated runtimes are tier A" "A" \
    "$(echo "$rules" | jq -r '.rules[] | select(.id=="simulator-runtimes-outdated") | .tier')"
assert_eq "unused runtimes are tier B" "B" \
    "$(echo "$rules" | jq -r '.rules[] | select(.id=="simulator-runtimes-unused") | .tier')"
assert_eq "test clones are tier B" "B" \
    "$(echo "$rules" | jq -r '.rules[] | select(.id=="xctest-device-clones") | .tier')"

# --- 実行前に、何がどれだけ消えるかが分かる
out="$("$DISCLEAN_BIN" scan --rule fake-runtimes --json --no-cache)"
item="$(echo "$out" | jq '.items[] | select(.ruleId=="fake-runtimes")')"
assert_eq "size is known before running" "true" "$(echo "$item" | jq '.sizeKnown')"
assert_eq "estimate includes the image and its shared cache" "true" \
    "$(echo "$item" | jq '.bytes >= 6000000 + 4194304 and .bytes < 9000000 + 6000000')"
assert_eq "says it cannot be undone" "false" "$(echo "$item" | jq '.undoable')"
assert_contains "names the runtime that goes away" "23B5059e" "$(echo "$item" | jq -r '.details[0]')"
assert_eq "scan deletes nothing" "2" "$(ls "$FAKE/images" | wc -l | tr -d ' ')"

human="$("$DISCLEAN_BIN" scan --rule fake-runtimes --no-cache 2>&1)"
assert_contains "human output lists the runtime" "iOS 26.1 (23B5059e)" "$human"
assert_contains "human output marks it not undoable" "not undoable" "$human"

# --- 実行すると消え、見せた量と同じだけ空いたと報告する
shown="$(echo "$item" | jq '.bytes')"
out="$("$DISCLEAN_BIN" apply --rule fake-runtimes --yes --json --no-cache)"
assert_eq "reports what was freed" "$shown" \
    "$(echo "$out" | jq '.commands[] | select(.ruleId=="fake-runtimes") | .reclaimedBytes')"
assert_eq "the outdated image is gone" "false" "$([ -e "$FAKE/images/$BETA.json" ] && echo true || echo false)"
assert_eq "the newer build stays" "true" "$([ -e "$FAKE/images/$RELEASE.json" ] && echo true || echo false)"

# --- 次のスキャンでは空なので出さない
out="$("$DISCLEAN_BIN" scan --rule fake-runtimes --json --no-cache)"
assert_eq "nothing left is skipped as empty" "empty" \
    "$(echo "$out" | jq -r '.items[] | select(.ruleId=="fake-runtimes") | .reason')"
human="$("$DISCLEAN_BIN" scan --rule fake-runtimes --no-cache 2>&1)"
assert_contains "an all-skipped scan still says why" "not listed: already empty 1" "$human"

finish AT-023

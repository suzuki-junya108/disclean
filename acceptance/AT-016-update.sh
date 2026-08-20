#!/bin/bash
# AT-016: 更新の検証・差分承認・オプトアウト（F-17）
# 署名検証はテスト鍵を注入するため debug ビルドで実行する（release では鍵注入が無効なので、
# その「無効であること」自体も AT-016 の最後で検証する）。
source "$(dirname "$0")/lib.sh"
setup_sandbox
trap cleanup EXIT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBUG_BIN="$REPO_ROOT/.build/debug/disclean"
CATALOG_TOOL="$REPO_ROOT/.build/debug/disclean-catalog"
SERVE_DIR="$SANDBOX/serve"
SERVER_PID=""

cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    teardown_sandbox
}

mkdir -p "$SERVE_DIR" "$SANDBOX/keys" "$SANDBOX/rules"

# 前回の実行が残したサーバがいるとテストが誤判定するため、先に片付ける。
pkill -f "http.server 4599" 2>/dev/null; sleep 1

# 1) テスト用の鍵を作り、信頼鍵として注入する（debug ビルドのみ有効）
"$CATALOG_TOOL" keygen --out "$SANDBOX/keys" --key-id test-key > /dev/null
export DISCLEAN_UPDATE_TRUSTED_KEYS_FILE="$SANDBOX/keys/test-key.release-keys.json"

# 2) 拡大差分（新ルール）を含むカタログを作る
mkdir -p "$HOME/Library/Caches/newtarget"
dd if=/dev/zero of="$HOME/Library/Caches/newtarget/a.bin" bs=1m count=1 2>/dev/null
cat > "$SANDBOX/rules/50-new.json" <<JSON
[{"id":"new-target","title":"new","tier":"A","kind":"directory",
  "paths":["$HOME/Library/Caches/newtarget"],"whatIsLost":"x"}]
JSON
"$CATALOG_TOOL" build --rules-dir "$SANDBOX/rules" --out-dir "$SERVE_DIR" \
    --catalog-version 2 --key-file "$SANDBOX/keys/test-key.private.key" --key-id test-key > /dev/null

ACCESS_LOG="$SANDBOX/access.log"
cd "$SERVE_DIR" && python3 -m http.server 4599 > "$ACCESS_LOG" 2>&1 &
SERVER_PID=$!
cd "$REPO_ROOT"

# CI では起動が遅れることがあるため、実際に応答するまで待つ（sleep では足りない）。
for _ in $(seq 1 50); do
    curl -sf -o /dev/null "http://127.0.0.1:4599/catalog-manifest.json" && break
    sleep 0.2
done
if ! curl -sf -o /dev/null "http://127.0.0.1:4599/catalog-manifest.json"; then
    echo "テスト用の配信サーバが起動しませんでした" >&2
    exit 1
fi

export DISCLEAN_UPDATE_ENDPOINT="http://127.0.0.1:4599/"
export DISCLEAN_AUTO_UPDATE=1

# --- AC1: 署名を改竄したら拒否する
cp "$SERVE_DIR/catalog-manifest.json.sig" "$SANDBOX/good.sig"
python3 - "$SERVE_DIR/catalog-manifest.json.sig" <<'PY'
import base64, sys
p = sys.argv[1]
raw = bytearray(base64.b64decode(open(p).read()))
raw[0] ^= 0x01
open(p, "w").write(base64.b64encode(bytes(raw)).decode())
PY
out="$("$DEBUG_BIN" update --check --json 2>&1)"; code=$?
assert_eq "tampered signature exits 7" 7 "$code"
assert_contains "reports the signature failure" "signature" "$out"
assert_eq "active catalog is untouched" "false" \
    "$([ -d "$DISCLEAN_STATE_DIR/updates/active" ] && echo true || echo false)"
cp "$SANDBOX/good.sig" "$SERVE_DIR/catalog-manifest.json.sig"

# --- AC3: 拡大差分は承認前に有効化されない
out="$("$DEBUG_BIN" update --check --json)"; code=$?
assert_eq "check exits 0" 0 "$code"
assert_eq "expanding change is detected" "true" "$(echo "$out" | jq '(.diff.expanding | length) >= 1')"
assert_eq "approval is required" "true" "$(echo "$out" | jq '.requiresApproval')"
assert_eq "not applied yet" "false" "$(echo "$out" | jq '.applied')"
assert_eq "new rule is not scanned yet" "0" \
    "$("$DEBUG_BIN" scan --json --no-update | jq '[.items[] | select(.ruleId=="new-target")] | length')"

# --- AC4: 承認すると適用される
out="$("$DEBUG_BIN" update --apply --yes --json)"; code=$?
assert_eq "apply exits 0" 0 "$code"
assert_eq "catalog 2 is applied" "2" "$(jq '.appliedCatalogVersion' "$DISCLEAN_STATE_DIR/updates/state.json")"
assert_eq "new rule is now visible" "1" \
    "$("$DEBUG_BIN" scan --json --no-update | jq '[.items[] | select(.ruleId=="new-target")] | length')"
assert_eq "the update is recorded in the audit log" "true" \
    "$("$DEBUG_BIN" history --json --no-update | jq '[.records[] | select(.action=="catalogUpdate")] | length >= 1')"

# --- AC2: 巻き戻し（古い版数）は拒否する
"$CATALOG_TOOL" build --rules-dir "$SANDBOX/rules" --out-dir "$SERVE_DIR" \
    --catalog-version 1 --key-file "$SANDBOX/keys/test-key.private.key" --key-id test-key > /dev/null
out="$("$DEBUG_BIN" update --check --json 2>&1)"; code=$?
assert_eq "rollback attempt exits 7" 7 "$code"
assert_contains "reports the rollback" "rollback-detected" "$out"
assert_eq "applied catalog stays at 2" "2" "$(jq '.appliedCatalogVersion' "$DISCLEAN_STATE_DIR/updates/state.json")"

# --- AC5: 無効化すると通信そのものが起きない
export DISCLEAN_AUTO_UPDATE=0
before="$(wc -l < "$ACCESS_LOG" | tr -d ' ')"
"$DEBUG_BIN" scan --json > /dev/null
"$DEBUG_BIN" doctor --json > /dev/null
sleep 1
after="$(wc -l < "$ACCESS_LOG" | tr -d ' ')"
assert_eq "no request while auto-update is off" "$before" "$after"
assert_eq "state file was not touched by a check" "2" "$(jq '.appliedCatalogVersion' "$DISCLEAN_STATE_DIR/updates/state.json")"

# --- release ビルドではテスト鍵の注入が効かない（信頼の起点は埋め込み鍵のみ）
export DISCLEAN_AUTO_UPDATE=1
rm -rf "$DISCLEAN_STATE_DIR/updates"
"$CATALOG_TOOL" build --rules-dir "$SANDBOX/rules" --out-dir "$SERVE_DIR" \
    --catalog-version 3 --key-file "$SANDBOX/keys/test-key.private.key" --key-id test-key > /dev/null
out="$("$DISCLEAN_BIN" update --check --json 2>&1)"; code=$?
assert_eq "release build rejects the test key (exit 7)" 7 "$code"
assert_contains "reports an unknown key" "unknown-key" "$out"

finish AT-016

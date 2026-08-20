# 受入テスト共通部品。実ユーザーの状態には触れず、必ず一時ディレクトリを使う。
set -uo pipefail

DISCLEAN_BIN="${DISCLEAN_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.build/release/disclean}"
PASS_COUNT=0
FAIL_COUNT=0

setup_sandbox() {
    SANDBOX="$(mktemp -d)"
    # PathGuard はホーム配下しか対象にしないため、HOME ごと一時ディレクトリに閉じ込める。
    # これで実ユーザーのファイルには一切触れずに、本番と同じ経路を検証できる。
    export HOME="$SANDBOX/home"
    export DISCLEAN_STATE_DIR="$SANDBOX/state"
    export DISCLEAN_CONFIG_DIR="$SANDBOX/config"
    export DISCLEAN_AUTO_UPDATE=0
    export DISCLEAN_LANG=en
    export NO_COLOR=1
    mkdir -p "$HOME/Library/Caches" "$DISCLEAN_STATE_DIR" "$DISCLEAN_CONFIG_DIR/rules.d"
}

teardown_sandbox() {
    [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

ok() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  ok   %s\n' "$1"
}

ng() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  FAIL %s\n' "$1"
}

# assert_eq <説明> <期待> <実際>
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (expected: $2, actual: $3)"; fi
}

# assert_contains <説明> <部分文字列> <全体>
assert_contains() {
    case "$3" in
        *"$2"*) ok "$1" ;;
        *) ng "$1 (missing: $2)" ;;
    esac
}

finish() {
    printf '%s: %d passed, %d failed\n' "$1" "$PASS_COUNT" "$FAIL_COUNT"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
}

#!/bin/bash
# ============================================================
#  mac_cleanup.sh - macOS ディスククリーンアップスクリプト
#  使い方: chmod +x mac_cleanup.sh && ./mac_cleanup.sh
#  ※ `sh mac_cleanup.sh` で起動された場合は自動的に bash で再実行します
# ============================================================

# bash 以外で起動された場合は bash で再実行（macOS の sh は bash の POSIX モードで
# echo -e がリテラル "-e " を出力してしまうため）
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

divider() { printf "${CYAN}──────────────────────────────────────────${NC}\n"; }

# ============================================================
#  timeout コマンドの検出とフォールバック
# ============================================================
# macOS には timeout が標準では無いので、GNU coreutils の timeout / gtimeout を
# 使えれば使い、無ければバックグラウンド + watchdog で代替する
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
fi

# with_timeout <秒数> <コマンド...>
# 成功: コマンドの終了コード / タイムアウト: 124
with_timeout() {
    local sec="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$sec" "$@"
        return $?
    fi

    # フォールバック: バックグラウンド実行 + 監視プロセス
    "$@" &
    local cmd_pid=$!

    (
        sleep "$sec"
        # まず TERM、ダメなら KILL
        kill -TERM "$cmd_pid" 2>/dev/null && {
            sleep 2
            kill -KILL "$cmd_pid" 2>/dev/null
        }
    ) >/dev/null 2>&1 &
    local wd_pid=$!

    local rc=0
    wait "$cmd_pid" 2>/dev/null
    rc=$?

    # watchdog を片付ける
    kill -TERM "$wd_pid" 2>/dev/null
    wait "$wd_pid" 2>/dev/null

    return "$rc"
}

printf "${GREEN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   🧹 Mac ディスククリーンアップ      ║"
echo "  ╚══════════════════════════════════════╝"
printf "${NC}\n"

if [ -z "$TIMEOUT_BIN" ]; then
    printf "${YELLOW}ℹ timeout/gtimeout コマンドが見つからないため、内蔵フォールバックを使用します${NC}\n"
    printf "${YELLOW}  (より確実にしたい場合: brew install coreutils)${NC}\n"
fi

# --- クリーンアップ前のディスク使用量 ---
BEFORE=$(df -h / | awk 'NR==2{print $4}')
printf "${YELLOW}▶ クリーンアップ前の空き容量: ${BEFORE}${NC}\n"
divider

cleaned=0
clean() {
    local label="$1" path="$2"
    if [ -d "$path" ]; then
        # du は巨大ディレクトリで遅くなることがあるのでタイムアウトを付ける
        local size
        size=$(with_timeout 10 du -sh "$path" 2>/dev/null | cut -f1)
        [ -z "$size" ] && size="計測不可"
        printf "${RED}🗑  ${label} (${size})${NC}\n"
        with_timeout 60 find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        cleaned=1
    else
        printf "  ⏭  ${label} - 見つかりません\n"
    fi
}

# ============================================================
#  1. システムキャッシュ・ログ
# ============================================================
printf "${GREEN}[1/7] システムキャッシュ・ログの削除${NC}\n"
clean "ユーザーキャッシュ"       "$HOME/Library/Caches"
clean "ユーザーログ"             "$HOME/Library/Logs"
clean "システムログ (要sudo)"    "/private/var/log"  # sudo 無しだと一部失敗するが問題なし

# ============================================================
#  2. Homebrew キャッシュ
# ============================================================
printf "${GREEN}[2/7] Homebrew キャッシュの削除${NC}\n"
if command -v brew >/dev/null 2>&1; then
    printf "  brew cleanup 実行中..."
    if with_timeout 120 brew cleanup --prune=all -s >/dev/null 2>&1; then
        printf " ✅ 完了\n"
    else
        printf " ${YELLOW}⚠ タイムアウト/エラー - キャッシュを直接削除します${NC}\n"
    fi
    # brew --cache 自体もまれにハングするのでタイムアウトを付ける
    brew_cache_dir=$(with_timeout 10 brew --cache 2>/dev/null || true)
    if [ -n "$brew_cache_dir" ] && [ -d "$brew_cache_dir" ]; then
        with_timeout 60 rm -rf "$brew_cache_dir" 2>/dev/null || true
    fi
else
    printf "  ⏭  Homebrew 未インストール - スキップ\n"
fi

# ============================================================
#  3. npm / yarn / pnpm キャッシュ
# ============================================================
printf "${GREEN}[3/7] Node.js パッケージマネージャーのキャッシュ削除${NC}\n"

run_step() {
    local label="$1" timeout_sec="$2"; shift 2
    printf "  %s 実行中..." "$label"
    if with_timeout "$timeout_sec" "$@" >/dev/null 2>&1; then
        printf " ✅ 完了\n"
    else
        printf " ${YELLOW}⚠ タイムアウトまたはエラー - スキップ${NC}\n"
    fi
}

if command -v npm >/dev/null 2>&1; then
    run_step "npm cache clean" 30 npm cache clean --force
fi

if command -v yarn >/dev/null 2>&1; then
    # yarn cache dir / clean はハングすることがあるので必ずタイムアウト経由で実行
    yarn_cache_dir=$(with_timeout 10 yarn cache dir 2>/dev/null || true)
    if [ -n "$yarn_cache_dir" ] && [ -d "$yarn_cache_dir" ]; then
        size=$(with_timeout 10 du -sh "$yarn_cache_dir" 2>/dev/null | cut -f1)
        [ -z "$size" ] && size="不明"
        printf "  ${RED}🗑  yarn cache (${size})${NC} - ディレクトリ直接削除\n"
        with_timeout 60 rm -rf "$yarn_cache_dir"/* 2>/dev/null || true
        printf "  ✅ yarn cache 削除\n"
    else
        printf "  ⏭  yarn cache ディレクトリ取得失敗 - スキップ\n"
    fi
fi

if command -v pnpm >/dev/null 2>&1; then
    run_step "pnpm store prune" 60 pnpm store prune
fi

# ============================================================
#  4. pip キャッシュ
# ============================================================
printf "${GREEN}[4/7] pip キャッシュの削除${NC}\n"
if command -v pip3 >/dev/null 2>&1; then
    printf "  pip cache purge 実行中..."
    if with_timeout 30 pip3 cache purge >/dev/null 2>&1; then
        printf " ✅ 完了\n"
    else
        # 直接削除にフォールバック
        with_timeout 30 rm -rf "$HOME/Library/Caches/pip" 2>/dev/null || true
        printf " ✅ ディレクトリ直接削除で完了\n"
    fi
else
    printf "  ⏭  pip3 未インストール - スキップ\n"
fi

# ============================================================
#  5. Xcode 関連 (開発者向け)
# ============================================================
printf "${GREEN}[5/7] Xcode 関連データの削除${NC}\n"
clean "Xcode DerivedData"       "$HOME/Library/Developer/Xcode/DerivedData"
clean "Xcode Archives"          "$HOME/Library/Developer/Xcode/Archives"
clean "CoreSimulator Caches"    "$HOME/Library/Developer/CoreSimulator/Caches"

# ============================================================
#  6. Docker (利用中の場合)
# ============================================================
printf "${GREEN}[6/7] Docker の不要データ削除${NC}\n"
if command -v docker >/dev/null 2>&1 && with_timeout 5 docker info >/dev/null 2>&1; then
    printf "  Docker system prune 実行中..."
    if with_timeout 180 docker system prune -af --volumes >/dev/null 2>&1; then
        printf " ✅ 完了\n"
    else
        printf " ${YELLOW}⚠ タイムアウト/エラー - スキップ${NC}\n"
    fi
else
    printf "  ⏭  Docker 未稼働 - スキップ\n"
fi

# ============================================================
#  7. その他の一般的なゴミ
# ============================================================
printf "${GREEN}[7/7] その他のクリーンアップ${NC}\n"
clean "Trash (ゴミ箱)"          "$HOME/.Trash"
clean "Adobe キャッシュ"         "$HOME/Library/Application Support/Adobe/Common/Media Cache Files"
clean "Spotify キャッシュ"       "$HOME/Library/Application Support/Spotify/PersistentCache"
clean "Google Chrome キャッシュ" "$HOME/Library/Caches/Google/Chrome"

# .DS_Store ファイル (ホームディレクトリ以下、深さ制限あり)
printf "  .DS_Store ファイル削除中..."
with_timeout 30 find "$HOME" -maxdepth 5 -name ".DS_Store" -delete 2>/dev/null || true
printf " ✅\n"

# ============================================================
#  結果レポート
# ============================================================
divider
AFTER=$(df -h / | awk 'NR==2{print $4}')
printf "${YELLOW}▶ クリーンアップ後の空き容量: ${AFTER}${NC}\n"
echo ""
printf "${GREEN}✨ クリーンアップ完了！ (${BEFORE} → ${AFTER})${NC}\n"

# --- 容量が大きいフォルダ TOP10 ---
divider
printf "${CYAN}📊 ホームディレクトリで容量が大きいフォルダ TOP10:${NC}\n"
with_timeout 30 du -sh "$HOME"/*/ 2>/dev/null | sort -rh | head -10 || printf "  取得できませんでした\n"
divider
printf "${YELLOW}💡 ヒント: 大きなファイルを探すには → find ~ -type f -size +500M${NC}\n"

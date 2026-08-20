#!/bin/bash
# 受入テストを全部走らせる。個別スクリプトはそれぞれ独立した一時 HOME で動く。
set -uo pipefail
cd "$(dirname "$0")"

TOTAL_FAIL=0
for script in AT-*.sh; do
    printf '\n== %s ==\n' "$script"
    if bash "$script"; then :; else TOTAL_FAIL=$((TOTAL_FAIL + 1)); fi
done

printf '\n----------------------------------------\n'
if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "acceptance: all suites passed"
    exit 0
fi
echo "acceptance: $TOTAL_FAIL suite(s) failed"
exit 1

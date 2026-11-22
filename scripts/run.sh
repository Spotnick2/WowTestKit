#!/usr/bin/env bash
# scripts/run.sh - CI's runner: syntax-check the TOC's Lua files (and any
# extra ones), then run every tests/test_*.lua under Lua 5.1, one process per
# file. From the repo root, with $WOWTESTKIT set:
#
#   bash "$WOWTESTKIT/scripts/run.sh" [Addon.toc] [extra.lua ...]
#
# $LUA / $LUAC name the interpreter and compiler (default lua5.1 / luac5.1):
# this script never installs anything.
set -uo pipefail

LUA="${LUA:-lua5.1}"
LUAC="${LUAC:-luac5.1}"
toc="${1:-}"
[ $# -gt 0 ] && shift

files=()
if [ -n "$toc" ]; then
    if [[ ! -f "$toc" || ! -r "$toc" ]]; then echo "Cannot read TOC: $toc" >&2; exit 1; fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "$line" in \#*|"") continue ;; esac
        case "$line" in *.lua) files+=("${line//\\//}") ;; esac
    done < "$toc" || exit 1
fi
files+=("$@")
if [ ${#files[@]} -gt 0 ]; then
    "$LUAC" -p "${files[@]}" || { echo "luac -p FAILED"; exit 1; }
    rm -f luac.out
    echo "luac -p: ok (${#files[@]} files)"
fi

failed=0 skipped=0 ran=0
shopt -s nullglob
pass_line='^.+: [0-9]+ passed, 0 failed$'
skip_line='^(.+: SKIPPED \(.+\)|SKIPPED: .+)$'
for f in tests/test_*.lua; do
    echo "-- $f"
    out="$("$LUA" "$f" 2>&1)"; code=$?
    printf '%s\n' "$out"
    # The result is the last line that isn't blank, as in run.ps1.
    last=$(printf '%s\n' "$out" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -n 1)
    ran=$((ran + 1))
    if [ $code -ne 0 ]; then failed=$((failed + 1))
    elif [[ $last =~ $skip_line ]]; then skipped=$((skipped + 1))
    elif [[ ! $last =~ $pass_line ]]; then
        echo "$f: missing successful final test result"
        failed=$((failed + 1))
    fi
done
if [ $ran -eq 0 ]; then echo "No tests/test_*.lua files found"; exit 1; fi
if [ $failed -gt 0 ]; then echo "$failed of $ran test file(s) FAILED"; exit 1; fi
echo "All $ran test files passed ($skipped skipped)."

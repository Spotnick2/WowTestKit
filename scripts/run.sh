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
    while IFS= read -r line; do
        line="${line//$'\r'/}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        case "$line" in \#*|"") continue ;; esac
        case "$line" in *.lua) files+=("${line//\\//}") ;; esac
    done < "$toc"
fi
files+=("$@")
if [ ${#files[@]} -gt 0 ]; then
    "$LUAC" -p "${files[@]}" || { echo "luac -p FAILED"; exit 1; }
    rm -f luac.out
    echo "luac -p: ok (${#files[@]} files)"
fi

failed=0 skipped=0 ran=0
for f in tests/test_*.lua; do
    echo "-- $f"
    out="$("$LUA" "$f" 2>&1)"; code=$?
    echo "$out"
    ran=$((ran + 1))
    if [ $code -ne 0 ]; then failed=$((failed + 1))
    elif echo "$out" | grep -q "SKIPPED"; then skipped=$((skipped + 1)); fi
done
if [ $failed -gt 0 ]; then echo "$failed of $ran test file(s) FAILED"; exit 1; fi
echo "All $ran test files passed ($skipped skipped)."

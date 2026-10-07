#!/bin/sh
# SPDX-License-Identifier: MIT
fail() { echo "$*" >&2; exit 2; }
absolute() {
    case "$1" in /*) ;; *) fail 'Use absolute paths.' ;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*) fail 'Use simple paths.' ;; esac
}
positive() {
    case "$2" in ''|*[!0-9]*) fail "$1 must be a positive integer." ;; esac
    [ "$2" -gt 0 ] 2>/dev/null || fail "$1 must be positive."
}
sha() {
    if command -v sha256 >/dev/null; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
verify_recipe() {
    while read -r source name expected; do
        [ "$(sha "$recipe/$name")" = "$expected" ] || fail "Patch checksum mismatch: $name"
    done < "$recipe/patches.tsv"
}
run() {
    stage=$1; shift
    result=0
    "$@" > "$work/logs/$stage.log" 2>&1 || result=$?
    if [ "$result" -ne 0 ]; then tail -60 "$work/logs/$stage.log" >&2; exit "$result"; fi
}

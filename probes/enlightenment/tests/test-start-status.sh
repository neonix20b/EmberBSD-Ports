#!/bin/sh
# Exercise the actual upstream exec-failure path without starting a desktop.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: test-start-status.sh SOURCE' >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/enlightenment-start-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cat > "$work/test.c" <<'C'
#include <stdio.h>
#include <unistd.h>
typedef int Eina_Bool;
static void _e_start_stdout_err_redir(const char *home) { (void)home; }
static void _e_ptrace_traceme(Eina_Bool know) { (void)know; }
C
awk '
    /^_e_start_child\(/ { copying=1; print "static int" }
    copying { print }
    copying && /^}/ { found=1; exit }
    END { if (!found) exit 1 }
' "$1/src/bin/e_start_main.c" >> "$work/test.c"
cat >> "$work/test.c" <<'C'
int main(void)
{
    char *args[] = { (char *)"/nonexistent/emberbsd-exec-regression", NULL };
    int status = _e_start_child("/nonexistent", args, 0, 0);
    if (status != 101) {
        fprintf(stderr, "exec failure returned %d, expected terminal error 101\n", status);
        return 1;
    }
    puts("PASS: failed exec returns terminal error 101");
    return 0;
}
C
cc -Wall -Wextra -Werror -O2 "$work/test.c" -o "$work/test"
"$work/test"

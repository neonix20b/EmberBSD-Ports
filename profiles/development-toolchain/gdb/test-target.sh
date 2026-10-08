#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), GDB external-DWARF and ptrace acceptance.
set -eu
[ "$#" = 4 ] || { echo "Usage: $0 GDB EXTERNAL_CTF_FIXTURES RUNTIME_FIXTURES NEW_WORK" >&2; exit 2; }
gdb=$1 external=$2 runtime=$3 work=$4
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
"$gdb" --version > "$work/version.txt"
grep -q '18.1' "$work/version.txt"
ldd "$gdb" > "$work/libraries.txt"
grep -q '/usr/pkg/gcc16/lib/libstdc++.so.7' "$work/libraries.txt"
"$gdb" -nx -nh -batch "$runtime/runtime-32" \
    -ex 'set host-charset utf-8' -ex 'print L"caf\u00e9"' \
    > "$work/charset.log" 2>&1
grep -q 'caf' "$work/charset.log"
if grep -Ei 'warning:|could not convert|Undefined item' "$work/charset.log"; then exit 1; fi
for name in gcc-32 gcc-64 clang-32 clang-64 sup-32-4 sup-32-8 sup-64-4 sup-64-8; do
    case $name in sup-*) symbol=ember_sup_global; size=16 ;; *) symbol=ember_data; size=72 ;; esac
    "$gdb" -nx -nh -batch "$external/$name/original.o" \
        -ex "ptype $symbol" -ex "printf \"SIZE=%d\\n\", sizeof($symbol)" \
        > "$work/$name.log" 2>&1
    grep -q "SIZE=$size" "$work/$name.log"
    if grep -Ei 'Dwarf Error|internal-error|Cannot handle|could not convert' "$work/$name.log"; then exit 1; fi
    case $name in sup-*)
        "$gdb" -nx -nh -batch "$external/$name/original.o" \
            -ex 'ptype ember_sup_inherited' > "$work/$name-inherited.log" 2>&1
        grep -q 'type = unsigned int' "$work/$name-inherited.log"
        ;;
    esac
done
echo 'PASS: GDB 18.1 reads eight external-DWARF objects and inherited supplementary types'

# Invalid supplementary metadata must produce a diagnostic, never a crash
# or the expected successful type lookup. Use regular local fixture files.
objcopy=${OBJCOPY:-/usr/bin/objcopy}
mkdir "$work/negative"
cp "$external/sup-32-4/original.o" "$work/negative/input.o"
cp "$external/sup-32-4/types.sup" "$work/negative/saved.sup"
for case_name in missing role filename leb overflow length identity; do
    cp "$work/negative/saved.sup" "$work/negative/types.sup"
    case $case_name in
    missing) rm "$work/negative/types.sup" ;;
    role) printf '\005\000\000\000\004EMBR' > "$work/header" ;;
    filename) printf '\005\000\001no-end' > "$work/header" ;;
    leb) printf '\005\000\001\000\200' > "$work/header" ;;
    overflow) printf '\005\000\001\000\377\377\377\377\377\377\377\377\377\377\001' > "$work/header" ;;
    length) printf '\005\000\001\000\010EMBR' > "$work/header" ;;
    identity) printf '\005\000\001\000\004FAIL' > "$work/header" ;;
    esac
    if [ "$case_name" != missing ]; then
        "$objcopy" --update-section ".debug_sup=$work/header" \
            "$work/negative/saved.sup" "$work/negative/types.sup"
    fi
    if "$gdb" -nx -nh -batch "$work/negative/input.o" -ex 'ptype ember_sup_global' \
        > "$work/negative-$case_name.log" 2>&1; then
        echo "GDB accepted invalid supplementary metadata: $case_name" >&2; exit 1
    else
        status=$?
        [ "$status" -lt 128 ] || { cat "$work/negative-$case_name.log"; exit 1; }
    fi
    if grep -q 'type = struct ember_sup_record' "$work/negative-$case_name.log"; then exit 1; fi
    grep -Ei 'debug_sup|supplement|dwz|alternate|alt debug' "$work/negative-$case_name.log" > /dev/null
done
echo 'PASS: missing supplements, invalid roles, strings, ID lengths and identity mismatches fail safely'

cp -R "$runtime" "$work/runtime"
line=$(awk '/DEBUGGER_STOP/ {print NR}' "$work/runtime/runtime.c")
signal_line=$(awk '/DEBUGGER_SIGNAL/ {print NR}' "$work/runtime/runtime.c")
for width in 32 64; do
    cat > "$work/commands-$width" <<EOF
set pagination off
set confirm off
directory $work/runtime
handle SIGUSR1 nostop noprint pass
break runtime.c:$line
break runtime.c:$signal_line
run
printf "LOCAL=%d ID=%ld FLAGS=%u\\n", local, debugger_data.id, debugger_data.flags
printf "FPCR=%lu FPSR=%lu\\n", \$fpcr, \$fpsr
backtrace
set variable local = 42
set \$fpcr = 0
set \$fpsr = 0
printf "CHANGED=%d\\n", local
continue
printf "SIGNAL=%d\\n", signo
printf "HANDLER_FPCR=%lu FPSR=%lu\\n", \$fpcr, \$fpsr
backtrace
frame 2
printf "SAVED_FPCR=%lu FPSR=%lu\\n", \$fpcr, \$fpsr
continue
quit
EOF
    (cd "$work/runtime"; "$gdb" -nx -nh -batch "./runtime-$width" \
        -x "$work/commands-$width") > "$work/runtime-$width.log" 2>&1
    grep -q 'LOCAL=41 ID=40 FLAGS=7' "$work/runtime-$width.log"
    grep -q 'CHANGED=42' "$work/runtime-$width.log"
    grep -q 'FPCR=16777216 FPSR=16' "$work/runtime-$width.log"
    grep -q 'SIGNAL=30' "$work/runtime-$width.log"
    grep -q 'HANDLER_FPCR=0 FPSR=0' "$work/runtime-$width.log"
    grep -q 'SAVED_FPCR=4194304 FPSR=8' "$work/runtime-$width.log"
    grep -q '#1 .*main' "$work/runtime-$width.log"
    grep -q '<signal handler called>' "$work/runtime-$width.log"
    grep -q 'exited normally' "$work/runtime-$width.log"
done
echo 'PASS: native breakpoints, locals, FP registers, signal unwinding and normal exit with split DWARF32/64'

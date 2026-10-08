#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), bounded native GDB DWARF matrix.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GDB FIXTURES NEW_RESULTS" >&2; exit 2; }
gdb=$1 fixtures=$2 work=$3
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ]
[ -z "${LD_LIBRARY_PATH-}${LD_PRELOAD-}" ] || { echo 'Remove loader overrides.' >&2; exit 2; }
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
fixtures=$(CDPATH= cd -- "$fixtures" && pwd)
"$gdb" --version > "$work/version.txt"
grep -q '18.1' "$work/version.txt"
readelf=${READELF:-/usr/pkg/bin/greadelf}
"$readelf" --version > "$work/readelf.txt"
uname -a > "$work/kernel.txt"
cat > "$work/c.commands" <<'COMMANDS'
set pagination off
set confirm off
break *variant_stop_one
break *variant_stop_two
run
printf "FIRST=%d ID=%ld FLAGS=%u TRACKED=%d\n", local, record.id, record.flags, tracked
backtrace
continue
printf "SECOND=%d ID=%ld FLAGS=%u TRACKED=%d\n", local, record.id, record.flags, tracked
backtrace
continue
quit
COMMANDS
cat > "$work/cpp.commands" <<'COMMANDS'
set pagination off
set confirm off
break *variant_cpp_stop
run
ptype record
printf "CPP_ID=%ld FLAGS=%u TRACKED=%d SIZE=%ld\n", record.id, record.flags, tracked, sizeof(record)
backtrace
continue
quit
COMMANDS
: > "$work/results.tsv"
failed=0
while read -r name language; do
    log=$work/$name.log
    mkdir -p "$(dirname -- "$log")"
    case $name in
    dwp-*)
        [ -e "$fixtures/$name.dwp" ]
        if find "$fixtures/${name%/program}" -name '*.dwo' | grep .; then
            echo 'Standalone DWO files must be unavailable in DWP acceptance.' >&2
            exit 2
        fi
        ;;
    esac
    status=PASS
    if ! (cd "$fixtures"; "$gdb" -nx -nh -batch "$name" \
        -ex "directory $fixtures" -x "$work/$language.commands") > "$log" 2>&1; then
        status=FAIL
    fi
    if grep -Ei 'Dwarf Error|internal-error|Cannot handle|could not convert|error:' "$log" > /dev/null; then
        status=FAIL
    fi
    case $language in
    c)
        grep -q 'FIRST=41 ID=40 FLAGS=7 TRACKED=42' "$log" || status=FAIL
        grep -q 'SECOND=44 ID=40 FLAGS=7 TRACKED=86' "$log" || status=FAIL
        ;;
    cpp)
        grep -q 'CPP_ID=40 FLAGS=7 TRACKED=42 SIZE=16' "$log" || status=FAIL
        grep -q 'VariantBase' "$log" || status=FAIL
        ;;
    *) echo "Invalid test language: $language" >&2; exit 2 ;;
    esac
    grep -q '#1 .*main' "$log" || status=FAIL
    grep -q 'exited normally' "$log" || status=FAIL
    printf '%s\t%s\n' "$name" "$status" | tee -a "$work/results.tsv"
    [ "$status" = PASS ] || failed=$((failed + 1))
done < "$fixtures/cases.tsv"
printf 'Failed cases: %s\n' "$failed"
[ "$failed" = 0 ]

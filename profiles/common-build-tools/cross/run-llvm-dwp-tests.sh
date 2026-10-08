#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), bounded package-index and live debugger checks.
set -eu
[ "$#" = 4 ] || { echo "Usage: $0 LLVM_DWP GDB FIXTURES NEW_RESULTS" >&2; exit 2; }
dwp=$1 gdb=$2 fixtures=$3 results=$4
readelf=${READELF:-/usr/pkg/bin/greadelf}
fixtures=$(CDPATH= cd -- "$fixtures" && pwd)
mkdir "$results"
results=$(CDPATH= cd -- "$results" && pwd)
run_dwp()
{
    (ulimit -c 0; ulimit -t 10; ulimit -f 2048; ulimit -v 1048576
     if [ -n "${LLVM_LIBRARY_PATH:-}" ]; then
         LD_LIBRARY_PATH=$LLVM_LIBRARY_PATH "$dwp" "$@"
     else
         "$dwp" "$@"
     fi)
}
run_dwp --version > "$results/dwp-version.txt"
"$gdb" --version > "$results/gdb-version.txt"
"$readelf" --version > "$results/readelf-version.txt"
: > "$results/results.tsv"
failed=0
while read -r name version types; do
    mkdir "$results/$name"
    cp "$fixtures/$name/program" "$results/$name/program"
    case_failed=0
    modes='direct repack'
    [ "$version" != 5 ] || modes="$modes promote"
    for mode in $modes; do
        output=$results/$name/program.dwp
        if [ "$mode" = direct ]; then
            if [ -f "$fixtures/$name/program.dwp" ]; then
                set -- "$fixtures/$name/program.dwp" "$fixtures/empty.o"
            else
                set -- "$fixtures/$name/main.dwo" "$fixtures/$name/helper.dwo"
            fi
        else
            mv "$output" "$results/$name/input.dwp"
            set -- "$results/$name/input.dwp"
            [ "$mode" != promote ] || set -- --dwarf64-str-offsets-promotion=always "$@"
        fi
        if ! run_dwp "$@" -o "$output" > "$results/$name/$mode-package.log" 2>&1; then
            printf 'FAIL\t%s\t%s-package\n' "$name" "$mode" >> "$results/results.tsv"
            case_failed=1
            break
        fi
        "$readelf" --debug-dump=cu_index "$output" > "$results/$name/$mode-index.txt" 2>&1
        if ! awk '/Contents of the .*debug_cu_index/ { cu=1 }
            cu && /Number of used entries:/ { found=1; if ($NF != 2) exit 1 }
            END { if (!found) exit 1 }' "$results/$name/$mode-index.txt"; then
            case_failed=1
        fi
        if [ "$types" = types ]; then
            grep -q '\.debug_tu_index' "$results/$name/$mode-index.txt" || case_failed=1
        fi
        # DWO inputs stay outside the executable directory, and the compiler's
        # original absolute build directory must not be mounted on this target.
        [ -z "$(find "$results/$name" -name '*.dwo' -print)" ] || exit 1
        cat > "$results/$name/$mode.gdb" <<'GDB'
set pagination off
set confirm off
set debuginfod enabled off
break package_stop
run
print value
print package_record.id
print package_record.flags
break package_touch
continue
print *value
backtrace
continue
GDB
        if ! (ulimit -t 20; ulimit -c 0; ulimit -v 1048576
              unset LD_LIBRARY_PATH LD_PRELOAD
              "$gdb" -q -nx -batch -x "$results/$name/$mode.gdb" \
                  "$results/$name/program") > "$results/$name/$mode-gdb.log" 2>&1; then
            case_failed=1
        fi
        log=$results/$name/$mode-gdb.log
        grep -q '\$1 = 41' "$log" || case_failed=1
        grep -q '\$2 = 40' "$log" || case_failed=1
        grep -q '\$3 = 7' "$log" || case_failed=1
        grep -q '\$4 = 41' "$log" || case_failed=1
        grep -q 'exited normally' "$log" || case_failed=1
        if grep -Ei 'Dwarf Error|Dwarf Warning|internal-error|Cannot find|Could not find' "$log"; then
            case_failed=1
        fi
        if [ "$case_failed" = 0 ]; then status=PASS; else status=FAIL; fi
        printf '%s\t%s\t%s\n' "$status" "$name" "$mode" >> "$results/results.tsv"
    done
    [ "$case_failed" = 0 ] || failed=1
done < "$fixtures/cases.tsv"
if [ ! -d "$fixtures/malformed" ]; then
    cat "$results/results.tsv"
    exit "$failed"
fi
for kind in short-header short-entry long-table bad-string short-unit long-unit \
    unterminated max-strx-w32 max-strx-w64 truncated-strx-w32 truncated-strx-w64; do
    for count in 1 2; do
        name=$kind-$count
        set -- "$fixtures/malformed/$kind.dwo"
        [ "$count" = 1 ] || set -- "$@" "$fixtures/v5-w64-64-plain/helper.dwo"
        set +e
        run_dwp "$@" -o "$results/$name.dwp" > "$results/$name.log" 2>&1
        rc=$?
        set -e
        status=PASS
        if [ "$rc" != 1 ] || [ -e "$results/$name.dwp" ] || \
            ! grep -Ei 'invalid|truncated|cannot parse|exceeds|unterminated' "$results/$name.log" >/dev/null; then
            status=FAIL
            failed=1
        fi
        printf '%s\t%s\tmalformed\n' "$status" "$name" >> "$results/results.tsv"
    done
done
for count in 1 2; do
    set -- "$fixtures/malformed/suffix-strings.dwo"
    [ "$count" = 1 ] || set -- "$@" "$fixtures/v5-w64-64-plain/helper.dwo"
    status=PASS
    if ! run_dwp "$@" -o "$results/suffix-$count.dwp" > "$results/suffix-$count.log" 2>&1; then
        status=FAIL
        failed=1
    fi
    printf '%s\tsuffix-%s\tvalid-string-offset\n' "$status" "$count" >> "$results/results.tsv"
done
cat "$results/results.tsv"
exit "$failed"

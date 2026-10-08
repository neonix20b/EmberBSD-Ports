#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), build bounded DWARF debugger fixtures.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GCC16_DRIVER SYSROOT NEW_WORK" >&2; exit 2; }
cc=$1 sysroot=$2 work=$3
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case $cc:$sysroot:$work in *' '*|*'
'*) echo 'Paths must not contain whitespace.' >&2; exit 2;; esac
cxx=${CXX:-${cc%gcc}g++}
objcopy=${OBJCOPY:-${cc%gcc}objcopy}
readelf=${READELF:-${cc%gcc}readelf}
crt=$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0/
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
cp "$here"/dwarf-variants.c "$here"/dwarf-variants-helper.c "$here"/dwarf-variants.cpp "$work/"
"$cc" --version > "$work/compiler.txt"
"$readelf" --version > "$work/readelf.txt"
: > "$work/cases.tsv"
cd "$work"
for version in 2 3 4 5; do
    for width in 32 64; do
        for opt in 0 2; do
            name=c-v$version-w$width-o$opt
            "$cc" --sysroot="$sysroot" -B"$crt" -O$opt -gdwarf-$version \
                -gdwarf$width -fno-omit-frame-pointer -std=gnu11 \
                -Wall -Wextra -Werror dwarf-variants.c dwarf-variants-helper.c -o "$name"
            "$readelf" --debug-dump=info "$name" > "$name.dwarf.txt"
            grep -q "Version: *$version" "$name.dwarf.txt"
            grep -q "($width-bit)" "$name.dwarf.txt"
            if [ "$opt" = 2 ]; then
                "$readelf" --wide --section-headers "$name" | grep -Eq '\.debug_loc(list)?s?'
                grep -q 'DW_OP_' "$name.dwarf.txt"
            fi
            printf '%s\tc\n' "$name" >> cases.tsv
        done
    done
done
for version in 4 5; do
    for width in 32 64; do
        name=cpp-v$version-w$width-types
        "$cxx" --sysroot="$sysroot" -B"$crt" -O2 -gdwarf-$version -gdwarf$width \
            -fdebug-types-section -std=c++20 -Wall -Wextra -Werror \
            dwarf-variants.cpp -o "$name"
        "$readelf" --debug-dump=info "$name" > "$name.dwarf.txt"
        grep -q 'DW_TAG_type_unit' "$name.dwarf.txt"
        grep -q 'DW_AT_signature' "$name.dwarf.txt"
        printf '%s\tcpp\n' "$name" >> cases.tsv
        name=dwp-v$version-w$width
        mkdir "$name"
        (cd "$name"
            "$cc" --sysroot="$sysroot" -B"$crt" -O2 -gdwarf-$version -gdwarf$width \
                -gsplit-dwarf -fno-omit-frame-pointer -std=gnu11 \
                -c ../dwarf-variants.c -o main.o
            "$cc" --sysroot="$sysroot" -B"$crt" -O2 -gdwarf-$version -gdwarf$width \
                -gsplit-dwarf -std=gnu11 -c ../dwarf-variants-helper.c -o helper.o
            "$cc" --sysroot="$sysroot" -B"$crt" main.o helper.o -o program
        )
    done
done
for width in 32 64; do
    for style in zlib-gnu zlib-gabi; do
        name=compressed-w$width-$style
        "$objcopy" --compress-debug-sections="$style" "c-v5-w$width-o2" "$name"
        "$readelf" --wide --section-headers "$name" > "$name.sections.txt"
        case $style in
        zlib-gnu) grep -q '\.zdebug_info' "$name.sections.txt" ;;
        zlib-gabi) grep '\.debug_info' "$name.sections.txt" | grep -q ' C ' ;;
        esac
        printf '%s\tc\n' "$name" >> cases.tsv
    done
    name=debuglink-w$width
    "$objcopy" --only-keep-debug "c-v5-w$width-o2" "$name.debug"
    "$objcopy" --strip-debug "c-v5-w$width-o2" "$name"
    "$objcopy" --add-gnu-debuglink="$name.debug" "$name"
    "$readelf" --wide --section-headers "$name" > "$name.sections.txt"
    grep -q '\.gnu_debuglink' "$name.sections.txt"
    if grep -q '\.debug_info' "$name.sections.txt"; then exit 1; fi
    printf '%s\tc\n' "$name" >> cases.tsv
done
for width in 32 64; do
    for kind in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
        define=
        [ "$width" != 64 ] || define=-DDW64
        "$cc" --sysroot="$sysroot" -B"$crt" $define -DKIND=$kind \
            "$here/dwarf-variants-limits.S" -o "limits-w$width-k$kind"
        "$readelf" --debug-dump=info "limits-w$width-k$kind" \
            > "limits-w$width-k$kind.dwarf.txt"
    done
done
printf 'Built %s direct cases and four two-CU DWP inputs.\n' "$(wc -l < cases.tsv | tr -d ' ')"

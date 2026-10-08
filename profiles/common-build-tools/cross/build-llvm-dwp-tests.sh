#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), compiler-produced DWP package fixtures.
set -eu
[ "$#" = 3 ] || { echo "Usage: $0 GCC16_DRIVER SYSROOT NEW_WORK" >&2; exit 2; }
cc=$1 sysroot=$2 work=$3
cxx=${CXX:-${cc%gcc}g++}
objcopy=${OBJCOPY:-${cc%gcc}objcopy}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$work"
work=$(CDPATH= cd -- "$work" && pwd)
crt=$sysroot/usr/pkg/gcc16/lib/gcc/aarch64--netbsd/16.2.0
cp "$here"/llvm-dwp-main.cpp "$here"/llvm-dwp-helper.cpp "$work/"
"$cxx" --version > "$work/compiler.txt"
: > "$work/cases.tsv"
for version in 4 5; do
    for widths in 32-32 64-64 32-64 64-32; do
        for types in plain types; do
            name=v$version-w$widths-$types
            mkdir "$work/$name"
            (cd "$work/$name"
                type_flags=
                [ "$types" != types ] || type_flags='-DTYPES -fdebug-types-section'
                "$cxx" --sysroot="$sysroot" -B"$crt/" -O0 -gdwarf-$version \
                    -gdwarf${widths%-*} -gsplit-dwarf $type_flags \
                    -fno-omit-frame-pointer -c ../llvm-dwp-main.cpp -o main.o
                "$cxx" --sysroot="$sysroot" -B"$crt/" -O0 -gdwarf-$version \
                    -gdwarf${widths#*-} -gsplit-dwarf \
                    -c ../llvm-dwp-helper.cpp -o helper.o
                "$cxx" --sysroot="$sysroot" -B"$crt/" main.o helper.o -o program
            )
            printf '%s\t%s\t%s\n' "$name" "$version" "$types" >> "$work/cases.tsv"
        done
    done
done
# Damage only generated copies. Retain original section payloads for provenance.
mkdir "$work/malformed"
"$objcopy" --dump-section .debug_str_offsets.dwo="$work/malformed/offsets.bin" \
    "$work/v5-w64-64-plain/main.dwo"
"$objcopy" --dump-section .debug_info.dwo="$work/malformed/info.bin" \
    "$work/v5-w64-64-plain/main.dwo"
"$objcopy" --dump-section .debug_str.dwo="$work/malformed/strings.bin" \
    "$work/v5-w64-64-plain/main.dwo"
ruby - "$work/malformed" <<'RUBY'
dir = ARGV.fetch(0)
offsets = File.binread("#{dir}/offsets.bin")
info = File.binread("#{dir}/info.bin")
File.binwrite("#{dir}/short-header.bin", offsets[0, 8])
File.binwrite("#{dir}/short-entry.bin", offsets[0...-1])
bad = offsets.dup
bad[4, 8] = [offsets.bytesize + 64].pack('Q<')
File.binwrite("#{dir}/long-table.bin", bad)
bad = offsets.dup
bad[16, 8] = [0xffffffffffffffff].pack('Q<')
File.binwrite("#{dir}/bad-string.bin", bad)
File.binwrite("#{dir}/short-unit.bin", info[0, 8])
bad = info.dup
bad[4, 8] = [0xffffffffffffffff].pack('Q<')
File.binwrite("#{dir}/long-unit.bin", bad)
File.binwrite("#{dir}/unterminated.bin", File.binread("#{dir}/strings.bin")[0...-1])
suffix = offsets + [1].pack('Q<')
suffix[4, 8] = [suffix.bytesize - 12].pack('Q<')
File.binwrite("#{dir}/suffix-strings.bin", suffix)
RUBY
for kind in short-header short-entry long-table bad-string short-unit long-unit unterminated suffix-strings; do
    section=.debug_str_offsets.dwo
    case $kind in *unit) section=.debug_info.dwo;; unterminated) section=.debug_str.dwo;; esac
    "$objcopy" --update-section "$section=$work/malformed/$kind.bin" \
        "$work/v5-w64-64-plain/main.dwo" "$work/malformed/$kind.dwo"
done
for width in 32 64; do
    define=
    [ "$width" != 64 ] || define=-DDW64
    for kind in max-strx truncated-strx; do
        extra=
        [ "$kind" != truncated-strx ] || extra=-DTRUNCATED
        "$cc" --sysroot="$sysroot" $define $extra -c "$here/llvm-dwp-malformed.S" \
            -o "$work/malformed/$kind-w$width.dwo"
    done
done
echo 'Built 16 two-CU DWP fixtures, 11 malformed inputs and a string-suffix input.'

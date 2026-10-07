#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted real ELF/Mach-O symbol-check regression.
set -eu
[ "$#" -eq 4 ] || {
    echo 'Usage: mesa-symbols-cross.sh MESA_SOURCE CROSS_PREFIX SYSROOT NEW_WORK' >&2
    exit 2
}
[ "$(uname -s)" = Darwin ] || { echo 'This regression needs a macOS host' >&2; exit 2; }
source_dir=$(CDPATH= cd -- "$1" && pwd -P)
prefix=$2 sysroot=$3 work=$4
python=${PYTHON:-python3.14}
[ ! -e "$work" ] && [ ! -L "$work" ]
mkdir "$work"
cat > "$work/api.c" <<'EOF'
#define OPTIONAL_IMPORT __attribute__((weak))
extern int optional_api(void) OPTIONAL_IMPORT;
extern int optional_data OPTIONAL_IMPORT;
int public_api(void) {
    int value = optional_api ? optional_api() : 42;
    return &optional_data ? value + optional_data : value;
}
#ifdef EXTRA_EXPORT
int unrelated_export(void) { return 17; }
#endif
#ifdef WEAK_EXPORT
__attribute__((weak)) int unrelated_export(void) { return 17; }
#endif
EOF
printf 'public_api\n' > "$work/api.txt"
"$prefix/bin/aarch64--netbsd-gcc" --sysroot="$sysroot" -shared -fPIC -nostdlib \
    "$work/api.c" -o "$work/api.so"
"$prefix/bin/aarch64--netbsd-gcc" --sysroot="$sysroot" -shared -fPIC -nostdlib \
    -DEXTRA_EXPORT "$work/api.c" -o "$work/extra.so"
"$prefix/bin/aarch64--netbsd-gcc" --sysroot="$sysroot" -shared -fPIC -nostdlib \
    -DWEAK_EXPORT "$work/api.c" -o "$work/weak-extra.so"
# The old host-based decision must reject real target ELF on Darwin.
if "$python" "$source_dir/bin/symbols-check.py" --nm "$prefix/bin/aarch64--netbsd-nm" \
    --lib "$work/api.so" --symbols-file "$work/api.txt" > "$work/host-red.log" 2>&1; then
    echo 'FAIL: native Darwin policy accepted NetBSD ELF' >&2; exit 1
fi
"$python" "$source_dir/bin/symbols-check.py" --target-system netbsd \
    --nm "$prefix/bin/aarch64--netbsd-nm" --lib "$work/api.so" --symbols-file "$work/api.txt"
status=0
"$python" "$source_dir/bin/symbols-check.py" --target-system netbsd \
    --nm "$prefix/bin/aarch64--netbsd-nm" --lib "$work/extra.so" --symbols-file "$work/api.txt" \
    > "$work/extra.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'unknown symbol exported: unrelated_export' "$work/extra.log"
status=0
"$python" "$source_dir/bin/symbols-check.py" --target-system netbsd \
    --nm "$prefix/bin/aarch64--netbsd-nm" --lib "$work/weak-extra.so" --symbols-file "$work/api.txt" \
    > "$work/weak-extra.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'unknown symbol exported: unrelated_export' "$work/weak-extra.log"
printf 'public_api\nmissing_api\n' > "$work/missing.txt"
status=0
"$python" "$source_dir/bin/symbols-check.py" --target-system netbsd \
    --nm "$prefix/bin/aarch64--netbsd-nm" --lib "$work/api.so" --symbols-file "$work/missing.txt" \
    > "$work/missing.log" 2>&1 || status=$?
[ "$status" -eq 1 ] && grep -q 'missing symbol: missing_api' "$work/missing.log"
# Native defaults still strip Mach-O's leading underscore.
printf 'int public_api(void) { return 42; }\n' > "$work/native.c"
"${HOST_CC:-cc}" -dynamiclib "$work/native.c" -o "$work/native.dylib"
"$python" "$source_dir/bin/symbols-check.py" --nm /usr/bin/nm \
    --lib "$work/native.dylib" --symbols-file "$work/api.txt"
echo 'PASS: real cross ELF, undefined weak imports, strong/weak extra and missing rejection, native Mach-O default'

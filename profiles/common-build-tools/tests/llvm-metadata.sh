#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), causal installed llvm-config metadata test.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 PRISTINE_LLVM_PROJECT NEW_WORK" >&2; exit 2; }
source=$1 work=$2
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake=${CMAKE:-cmake}
mkdir "$work"
mkdir -p "$work/fixed/tools/llvm-config"
input=$source/llvm/tools/llvm-config/CMakeLists.txt
cp "$input" "$work/fixed/tools/llvm-config/"
patch -f -N -F 0 -p0 -d "$work/fixed" < \
    "$root/recipes/lang/llvm/patches/patch-tools_llvm-config_CMakeLists.txt" > "$work/patch.log"
if grep -Ei 'offset|fuzz|FAILED' "$work/patch.log"; then exit 1; fi
for variant in baseline fixed; do
    file=$input
    [ "$variant" != fixed ] || file=$work/fixed/tools/llvm-config/CMakeLists.txt
    # Execute the upstream metadata assignment and its patched continuation.
    # The linker flag variable remains observable separately.
    awk '/^set\(LLVM_LDFLAGS / {active=1} /^set\(LLVM_BUILDMODE / {exit} active {print}' \
        "$file" > "$work/$variant.cmake"
    test -s "$work/$variant.cmake"
    for mode in native cross no-sysroot; do
        cross=ON sysroot=/private/target-root
        [ "$mode" != native ] || cross=OFF
        [ "$mode" != no-sysroot ] || sysroot=
        cat > "$work/case.cmake" <<EOF
set(CMAKE_CROSSCOMPILING $cross)
set(CMAKE_SYSROOT "$sysroot")
set(CMAKE_CXX_LINK_FLAGS "-L/private/target-root/usr/pkg/gcc16/lib -Wl,-rpath,/usr/pkg/gcc16/lib -L/usr/lib")
include("$work/$variant.cmake")
file(WRITE "$work/$variant-$mode.txt" "\${LLVM_LDFLAGS}\n\${CMAKE_CXX_LINK_FLAGS}\n")
EOF
        "$cmake" -P "$work/case.cmake"
        tail -1 "$work/$variant-$mode.txt" | grep -Fq -- '-L/private/target-root/usr/pkg/gcc16/lib'
        if [ "$variant:$mode" = fixed:cross ]; then
            head -1 "$work/$variant-$mode.txt" | grep -Fx -- '-L/usr/pkg/gcc16/lib -Wl,-rpath,/usr/pkg/gcc16/lib -L/usr/lib'
        else
            head -1 "$work/$variant-$mode.txt" | grep -Fq -- '-L/private/target-root/usr/pkg/gcc16/lib'
        fi
    done
done
echo 'PASS: cross metadata loses only its build sysroot; build flags and native/no-sysroot paths remain intact.'

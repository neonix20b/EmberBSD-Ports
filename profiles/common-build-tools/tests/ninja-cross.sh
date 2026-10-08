#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), cross build drivers and pkgsrc job policy.
set -eu
[ "$#" = 4 ] || { echo "Usage: $0 PKGSRC CROSS_MAKECONF NATIVE_MAKECONF NEW_WORK" >&2; exit 2; }
pkgsrc=$1 crossconf=$2 nativeconf=$3 work=$4
bmake=${BMAKE:-bmake}
mkdir "$work"
cat > "$work/default.mk.conf" <<EOF
.include "$crossconf"
.undef MAKE_JOBS
EOF
"$bmake" -C "$pkgsrc/devel/ninja-build" MAKECONF="$work/default.mk.conf" \
    -n do-build > "$work/default-command.txt"
grep -q '/bin/ninja -j1 ninja' "$work/default-command.txt"
grep -q -- '--platform=netbsd --host=darwin' "$work/default-command.txt"
if grep -q -- '--bootstrap' "$work/default-command.txt"; then
    echo 'Cross build attempts to bootstrap the target executable' >&2; exit 1
fi
tool_python=$("$bmake" -C "$pkgsrc/devel/ninja-build" MAKECONF="$crossconf" -v TOOL_PYTHONBIN)
grep -Fq "$tool_python ./configure.py" "$work/default-command.txt"
"$bmake" -C "$pkgsrc/devel/ninja-build" MAKECONF="$crossconf" \
    MAKE_JOBS=8 MAKE_JOBS_SAFE=no -n do-build > "$work/unsafe-command.txt"
grep -q '/bin/ninja -j1 ninja' "$work/unsafe-command.txt"
"$bmake" -C "$pkgsrc/devel/ninja-build" MAKECONF="$crossconf" \
    MAKE_JOBS=2 -n do-build > "$work/parallel-command.txt"
grep -q '/bin/ninja -j2 ninja' "$work/parallel-command.txt"
"$bmake" -C "$pkgsrc/devel/ninja-build" MAKECONF="$nativeconf" \
    -n do-build > "$work/native-command.txt"
grep -q './configure.py --bootstrap' "$work/native-command.txt"
echo 'PASS: host Python/Ninja cross drivers, retained native bootstrap and pkgsrc job limits'

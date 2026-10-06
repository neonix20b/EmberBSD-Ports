#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
set -eu
umask 077
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixtures=$(mktemp -d "${TMPDIR:-/tmp}/emberbsd-client-ldd.XXXXXXXX")
trap 'rm -rf "$fixtures"' EXIT HUP INT TERM
cat > "$fixtures/good" <<'EOF'
/probe/client:
    -lQt6Core.6 => /usr/pkg/qt6/lib/libQt6Core.so.6
    -lstdc++.9 => /usr/lib/libstdc++.so.9
    -lc.12 => /usr/lib/libc.so.12
EOF
sed 's|/usr/lib/libstdc++.so.9|/usr/pkg/gcc/lib/libstdc++.so.9|' "$fixtures/good" > "$fixtures/wrong-path"
sed 's/-lstdc++.9/-lstdc++.7/;s/libstdc++.so.9/libstdc++.so.7/' "$fixtures/good" > "$fixtures/wrong-version"
cp "$fixtures/good" "$fixtures/mixed"
printf '\t-lstdc++.7 => /usr/pkg/gcc/lib/libstdc++.so.7\n' >> "$fixtures/mixed"
cp "$fixtures/good" "$fixtures/missing"
printf '\t-lQt6DBus.6 => not found\n' >> "$fixtures/missing"
sed '/stdc++/d' "$fixtures/good" > "$fixtures/absent-runtime"
awk -f "$test_dir/check-netbsd-ldd.awk" "$fixtures/good"
for name in wrong-path wrong-version mixed missing absent-runtime; do
    if awk -f "$test_dir/check-netbsd-ldd.awk" "$fixtures/$name"; then
        echo "ABI parser incorrectly accepted $name" >&2
        exit 1
    fi
done
echo 'NetBSD ldd parser regression passed: 6 cases'

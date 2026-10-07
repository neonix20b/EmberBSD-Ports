#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; reject accidental system-library fallback in the target runner.
set -eu
runner=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/run-libdrm-tests.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/libdrm-runner.XXXXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/bin" "$work/bundle" "$work/foreign"
cp "$runner" "$work/bundle/"
touch "$work/bundle/libdrm.so.2.134.0" "$work/foreign/libdrm.so.2.134.0"
ln -s libdrm.so.2.134.0 "$work/bundle/libdrm.so.2"
cat > "$work/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo NetBSD;; -p) echo aarch64;; *) echo 'Mock NetBSD';; esac
EOF
cat > "$work/bin/ldd" <<'EOF'
#!/bin/sh
path=$TEST_BUNDLE/libdrm.so.2
if [ "$1" = "./${TEST_PROGRAM:-none}" ]; then
    case "$TEST_MODE" in
        foreign) path=$TEST_FOREIGN/libdrm.so.2.134.0;;
        missing) exit 0;;
        ambiguous) echo "-ldrm.2 => $path";;
    esac
fi
echo "-ldrm.2 => $path"
echo '-lc.12 => /usr/lib/libc.so.12'
EOF
for program in hash drmsl drmdevice; do
    cat > "$work/bundle/$program" <<'EOF'
#!/bin/sh
echo invoked >> "$TEST_MARKER"
EOF
done
chmod +x "$work/bin/"* "$work/bundle/hash" "$work/bundle/drmsl" "$work/bundle/drmdevice"
PATH=$work/bin:$PATH
export PATH
TEST_BUNDLE=$(CDPATH= cd "$work/bundle" && pwd -P)
TEST_FOREIGN=$(CDPATH= cd "$work/foreign" && pwd -P)
TEST_MARKER=$work/invoked
export TEST_BUNDLE TEST_FOREIGN TEST_MARKER
PYTHON=true
export PYTHON
for TEST_MODE in foreign missing ambiguous; do
    for TEST_PROGRAM in hash drmsl drmdevice; do
        export TEST_MODE TEST_PROGRAM
        rm -f "$TEST_MARKER"
        if sh "$TEST_BUNDLE/run-libdrm-tests.sh" > "$work/result" 2>&1; then
            echo "FAIL: accepted $TEST_MODE dependency for $TEST_PROGRAM" >&2
            exit 1
        fi
        [ ! -e "$TEST_MARKER" ] || { echo 'FAIL: executed before identity checks' >&2; exit 1; }
    done
done
unset TEST_MODE TEST_PROGRAM
ln -sf "$TEST_FOREIGN/libdrm.so.2.134.0" "$TEST_BUNDLE/libdrm.so.2"
if sh "$TEST_BUNDLE/run-libdrm-tests.sh" > "$work/result" 2>&1; then
    echo 'FAIL: accepted local symlink to foreign DSO' >&2; exit 1
fi
[ ! -e "$TEST_MARKER" ]
ln -sf libdrm.so.2.134.0 "$TEST_BUNDLE/libdrm.so.2"
sh "$TEST_BUNDLE/run-libdrm-tests.sh" > "$work/result" 2>&1
[ "$(wc -l < "$TEST_MARKER" | tr -d ' ')" -eq 3 ]
echo 'PASS: 10 invalid loader resolutions rejected before execution; local DSO accepted'

#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; verify corrupt target bundles stop before loader execution.
set -eu
[ "$#" -eq 1 ] || { echo 'Usage: mesa-bundle-integrity.sh NEW_WORK' >&2; exit 2; }
[ ! -e "$1" ] && [ ! -L "$1" ]
mkdir "$1"
work=$(CDPATH= cd -- "$1" && pwd -P)
profile=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir "$work/bin"
cat > "$work/bin/uname" <<'SH'
#!/bin/sh
case "$1" in -s) echo NetBSD;; -p) echo aarch64;; *) exit 2;; esac
SH
cat > "$work/bin/sha256" <<'SH'
#!/bin/sh
[ "$1" = -q ] || exit 2
shasum -a 256 "$2" | awk '{ print $1 }'
SH
cat > "$work/bin/ldd" <<'SH'
#!/bin/sh
echo 'unexpected loader execution' > "$MESA_TEST_LOADER_MARKER"
exit 1
SH
chmod +x "$work/bin/"*
for changed in executable dso; do
    bundle=$work/$changed
    mkdir -p "$bundle/tests" "$bundle/lib"
    cp "$profile/cross/run-mesa-upstream.sh" "$bundle/"
    printf 'executable fixture\n' > "$bundle/tests/test"
    printf 'library fixture\n' > "$bundle/lib/libfixture.so"
    printf 'test\ttest\n' > "$bundle/upstream-tests.tsv"
    (cd "$bundle"; find . -type f ! -name artifacts.sha256 -exec shasum -a 256 {} \; |
        LC_ALL=C sort -k2 > artifacts.sha256)
    case "$changed" in
        executable) damaged=./tests/test;;
        dso) damaged=./lib/libfixture.so;;
    esac
    printf 'changed\n' >> "$bundle/$damaged"
    status=0
    PATH="$work/bin:$PATH" MESA_TEST_LOADER_MARKER="$bundle/loader-ran" \
        sh "$bundle/run-mesa-upstream.sh" > "$work/$changed.log" 2>&1 || status=$?
    [ "$status" -eq 1 ]
    grep -F "Artifact checksum mismatch: $damaged" "$work/$changed.log"
    [ ! -e "$bundle/loader-ran" ]
done
echo 'PASS: modified executable and DSO rejected before ldd or target tests'

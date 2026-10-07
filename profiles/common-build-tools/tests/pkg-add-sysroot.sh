#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), real pkg_add alternate-root replacement regression.
set -eu
[ "$#" = 4 ] || { echo "Usage: $0 ORIGINAL_PKG_ADD FIXED_PKG_ADD PKG_CREATE NEW_WORK" >&2; exit 2; }
original=$1 fixed=$2 create=$3 work=$4
for path do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!a-zA-Z0-9_./-]*) exit 2 ;; esac
done
mkdir "$work"
mkdir -p "$work/payload/share/ember-cross-test"
printf 'Cross package replacement fixture\n' > "$work/comment"
cp "$work/comment" "$work/description"
cat > "$work/script" <<'SCRIPT'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >> "${EMBER_PKG_SCRIPT_TRACE:?}"
SCRIPT
chmod +x "$work/script"
printf 'OPSYS=NetBSD\nMACHINE_ARCH=aarch64\nOS_VERSION=11.0\nPKGTOOLS_VERSION=20260227\n' > "$work/native-info"
cp "$work/native-info" "$work/cross-info"
printf 'REQUIRES=/usr/lib/libember-cross-test.so\n' >> "$work/cross-info"
cp "$work/cross-info" "$work/before-info"
for mode in before cross native; do
    for version in 1.0 2.0; do
        printf '%s\n' "$version" > "$work/payload/share/ember-cross-test/version"
        printf '@name ember-cross-test-%s\nshare/ember-cross-test/version\n' "$version" > "$work/plist"
        if [ "$mode" != before ]; then
            printf '@pkgdir share/ember-cross-test/empty\n@exec echo exec >> "$EMBER_PKG_SCRIPT_TRACE"\n@unexec echo unexec >> "$EMBER_PKG_SCRIPT_TRACE"\n' >> "$work/plist"
        fi
        "$create" -p "$work/payload" -I /usr/pkg -f "$work/plist" \
            -c "$work/comment" -d "$work/description" -i "$work/script" -k "$work/script" \
            -B "$work/$mode-info" "$work/$mode-$version.tgz"
    done
done
export EMBER_PKG_SCRIPT_TRACE="$work/cross-script-executed"
for mode in before after; do
    case "$mode" in before) add=$original; package=before ;; after) add=$fixed; package=cross ;; esac
    mkdir -p "$work/$mode/usr/lib"
    # pkg_add checks the existence of REQUIRES; this is deliberately not an ELF test.
    : > "$work/$mode/usr/lib/libember-cross-test.so"
    "$add" -m 'NetBSD/aarch64 11.0' -I -K /usr/pkg/pkgdb -P "$work/$mode" "$work/$package-1.0.tgz"
    if "$add" -m 'NetBSD/aarch64 11.0' -I -U -K /usr/pkg/pkgdb -P "$work/$mode" \
        "$work/$package-2.0.tgz" > "$work/$mode-replace.log" 2>&1; then
        [ "$mode" = after ] || { echo 'Pristine replacement unexpectedly passed' >&2; exit 1; }
    else
        [ "$mode" = before ] || { cat "$work/$mode-replace.log" >&2; exit 1; }
    fi
done
[ ! -e "$EMBER_PKG_SCRIPT_TRACE" ]
[ "$(cat "$work/after/usr/pkg/share/ember-cross-test/version")" = 2.0 ]
[ ! -e "$work/after/usr/pkg/pkgdb/ember-cross-test-1.0" ]
[ -d "$work/after/usr/pkg/share/ember-cross-test/empty" ]
grep -Fxq '@cwd /usr/pkg' "$work/after/usr/pkg/pkgdb/ember-cross-test-2.0/+CONTENTS"
"$fixed" -m 'NetBSD/aarch64 11.0' -I -U -K /usr/pkg/pkgdb -P "$work/after" \
    "$work/cross-2.0.tgz" > "$work/same-version.log" 2>&1
[ ! -e "$EMBER_PKG_SCRIPT_TRACE" ]
echo 'PASS: original replacement fails; fixed update and same-version reinstall preserve target paths and skip target scripts'

# Another package's ownership protects an empty parent after the file is removed.
mkdir -p "$work/payload/share/common"
printf '@name ember-cross-dir-1.0\n@pkgdir share/common\n' > "$work/plist"
"$create" -p "$work/payload" -I /usr/pkg -f "$work/plist" \
    -c "$work/comment" -d "$work/description" -B "$work/cross-info" "$work/owner.tgz"
printf 'shared directory payload\n' > "$work/payload/share/common/file"
printf '@name ember-cross-file-1.0\nshare/common/file\n' > "$work/plist"
"$create" -p "$work/payload" -I /usr/pkg -f "$work/plist" \
    -c "$work/comment" -d "$work/description" -B "$work/cross-info" "$work/file.tgz"
"$fixed" -m 'NetBSD/aarch64 11.0' -I -K /usr/pkg/pkgdb -P "$work/after" "$work/owner.tgz" "$work/file.tgz"
"$(dirname "$fixed")/pkg_delete" -D -K /usr/pkg/pkgdb -P "$work/after" ember-cross-file
[ -d "$work/after/usr/pkg/share/common" ]
[ ! -e "$work/after/usr/pkg/share/common/file" ]
echo 'PASS: removing a file preserves a directory owned by another target package'

# Force an extraction failure after the first payload file has been written.
mkdir -p "$work/payload/share/rollback" "$work/after/usr/pkg/share/rollback/blocked"
printf 'first\n' > "$work/payload/share/rollback/first"
printf 'blocked\n' > "$work/payload/share/rollback/blocked"
printf 'preserve existing data\n' > "$work/after/usr/pkg/share/rollback/blocked/keep"
printf '@name ember-cross-rollback-1.0\nshare/rollback/first\n@exec echo exec >> "$EMBER_PKG_SCRIPT_TRACE"\nshare/rollback/blocked\n@unexec echo unexec >> "$EMBER_PKG_SCRIPT_TRACE"\n' > "$work/plist"
"$create" -p "$work/payload" -I /usr/pkg -f "$work/plist" \
    -c "$work/comment" -d "$work/description" -i "$work/script" -k "$work/script" \
    -B "$work/cross-info" "$work/rollback.tgz"
if "$fixed" -m 'NetBSD/aarch64 11.0' -I -K /usr/pkg/pkgdb -P "$work/after" \
    "$work/rollback.tgz" > "$work/rollback.log" 2>&1; then
    echo 'Extraction over a nonempty directory unexpectedly passed' >&2; exit 1
fi
[ ! -e "$EMBER_PKG_SCRIPT_TRACE" ]
[ ! -e "$work/after/usr/pkg/share/rollback/first" ]
[ ! -e "$work/after/usr/pkg/pkgdb/ember-cross-rollback-1.0" ]
[ "$(cat "$work/after/usr/pkg/share/rollback/blocked/keep")" = 'preserve existing data' ]
"$(dirname "$fixed")/pkg_admin" -K "$work/after/usr/pkg/pkgdb" dump > "$work/rollback-owner.log"
if grep -Fq 'pkg: ember-cross-rollback-1.0' "$work/rollback-owner.log"; then echo "Unexpected matching output" >&2; exit 1; fi
if grep -Fq 'file: /usr/pkg/share/rollback/first ' "$work/rollback-owner.log"; then echo "Unexpected matching output" >&2; exit 1; fi
if grep -Fq 'file: /usr/pkg/share/rollback/blocked ' "$work/rollback-owner.log"; then echo "Unexpected matching output" >&2; exit 1; fi
echo 'PASS: partial-extraction rollback removes files and ownership without executing target commands'

export EMBER_PKG_SCRIPT_TRACE="$work/native-script-executed"
"$fixed" -m 'NetBSD/aarch64 11.0' -I -K "$work/native-db" -p "$work/native-prefix" "$work/native-1.0.tgz"
"$fixed" -m 'NetBSD/aarch64 11.0' -I -U -K "$work/native-db" -p "$work/native-prefix" \
    "$work/native-2.0.tgz" > "$work/native-replace.log" 2>&1
[ -s "$EMBER_PKG_SCRIPT_TRACE" ]
[ "$(cat "$work/native-prefix/share/ember-cross-test/version")" = 2.0 ]
echo 'PASS: native replacement retains its existing deinstall-script behavior'

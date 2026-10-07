#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted exporter temporary-file regression.
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 NEW_WORK" >&2; exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
mkdir "$1"
work=$(CDPATH= cd -- "$1" && pwd)
mkdir "$work/cwd" "$work/tmp" "$work/bin"
first=$(awk -F '\t' '!/^#/ && NF { print $1; exit }' "$root/probes/plasma-mobile/toolkit/sources.tsv")
archive=$(awk -F '\t' '!/^#/ && NF { print $2; exit }' "$root/probes/plasma-mobile/toolkit/sources.tsv")
printf 'Caller-owned archive sentinel\n' > "$work/cwd/$archive"
cp "$work/cwd/$archive" "$work/expected"
REAL_CP=$(command -v cp)
export REAL_CP
cat > "$work/bin/cp" <<'CP'
#!/bin/sh
for argument do
    if [ -n "${TOOLKIT_TEST_FAIL_SOURCE:-}" ] && [ "$argument" = "$TOOLKIT_TEST_FAIL_SOURCE" ]; then exit 42; fi
done
exec "$REAL_CP" "$@"
CP
chmod +x "$work/bin/cp"
result=0
(cd "$work/cwd" && PATH="$work/bin:$PATH" TMPDIR="$work/tmp" \
    TOOLKIT_TEST_FAIL_SOURCE="$root/probes/plasma-mobile/toolkit/recipes/$first" \
    sh "$root/scripts/prepare-pkgsrc.sh" "$work/failed-export" plasma-mobile) \
    > "$work/failed.log" 2>&1 || result=$?
[ "$result" -eq 42 ] || { echo "Failure status changed: $result" >&2; exit 1; }
cmp "$work/expected" "$work/cwd/$archive"
[ -z "$(ls -A "$work/tmp")" ] || { echo 'Failed export leaked its archive.' >&2; exit 1; }
(cd "$work/cwd" && PATH="$work/bin:$PATH" TMPDIR="$work/tmp" \
    sh "$root/scripts/prepare-pkgsrc.sh" "$work/success-export" plasma-mobile) \
    > "$work/success.log" 2>&1
cmp "$work/expected" "$work/cwd/$archive"
[ -z "$(ls -A "$work/tmp")" ] || { echo 'Successful export leaked its archive.' >&2; exit 1; }
echo 'PASS: successful/failed exports clean their own temporary archive and preserve caller files'

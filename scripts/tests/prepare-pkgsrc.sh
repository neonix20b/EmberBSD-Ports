#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-pkgsrc-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir "$work/existing" "$work/bin"
printf preserve > "$work/existing/sentinel"
if sh "$root/scripts/prepare-pkgsrc.sh" "$work/existing"; then exit 1; fi
[ "$(cat "$work/existing/sentinel")" = preserve ]
if sh "$root/scripts/prepare-pkgsrc.sh" relative-path; then exit 1; fi
cat > "$work/bin/git" <<'STUB'
#!/bin/sh
case "$*" in
    *ls-files*) printf '160000 1111111111111111111111111111111111111111 0\tupstream/pkgsrc\n' ;;
    *rev-parse*) printf '2222222222222222222222222222222222222222\n' ;;
    *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/git"
if PATH="$work/bin:$PATH" sh "$root/scripts/prepare-pkgsrc.sh" "$work/mismatch"; then exit 1; fi
[ ! -e "$work/mismatch" ]
echo 'PASS: existing destination, relative path, mismatched submodule revision'

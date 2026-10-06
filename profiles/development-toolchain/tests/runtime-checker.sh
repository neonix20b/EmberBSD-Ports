#!/bin/sh
# Unit checks for rejecting a second or incorrectly resolved C++ runtime.
# These fixtures are not native ABI evidence.
set -eu
source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ember-gcc-runtime-check.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mkdir -p "$work/gcc16/bin" "$work/gcc16/lib" "$work/base" "$work/result"
touch "$work/gcc16/lib/libstdc++.so.7" "$work/gcc16/lib/libgcc_s.so.1" \
    "$work/base/libstdc++.so.9"
ln -s libstdc++.so.7 "$work/gcc16/lib/libstdc++.so"
ln -s libgcc_s.so.1 "$work/gcc16/lib/libgcc_s.so"
cat > "$work/gcc16/bin/g++" <<'COMPILER'
#!/bin/sh
prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$1" in
    -print-file-name=libstdc++.so) echo "$prefix/lib/libstdc++.so" ;;
    -print-file-name=libgcc_s.so) echo "$prefix/lib/libgcc_s.so" ;;
    *) exit 2 ;;
esac
COMPILER
chmod +x "$work/gcc16/bin/g++"
# Normalize /tmp on systems where it is a symlink.
work=$(CDPATH= cd -- "$work" && pwd -P)
printf 'LOADED %s\n' "$work/gcc16/lib/libstdc++.so.7" \
    "$work/gcc16/lib/libgcc_s.so.1" > "$work/result/loaded.txt"
sh "$source/check-runtime.sh" "$work/gcc16" "$work/result"
printf 'LOADED %s\n' "$work/base/libstdc++.so.9" >> "$work/result/loaded.txt"
if sh "$source/check-runtime.sh" "$work/gcc16" "$work/result"; then exit 1; fi
printf 'LOADED %s\n' "$work/base/libstdc++.so.9" \
    "$work/gcc16/lib/libgcc_s.so.1" > "$work/result/loaded.txt"
if sh "$source/check-runtime.sh" "$work/gcc16" "$work/result"; then exit 1; fi
echo 'PASS: checker accepts matching paths and rejects dual/wrong C++ runtime fixtures'

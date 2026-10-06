#!/bin/sh
set -eu
umask 077
[ "$#" -eq 1 ] || { echo 'Usage: sh check.sh NEW_RESULT_DIRECTORY' >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir "$1"
out=$(CDPATH= cd -- "$1" && pwd)
pkgconf=${PKG_CONFIG:-pkg-config}
command -v "$pkgconf" >/dev/null
cflags=$("$pkgconf" --cflags sqlite3)
libs=$("$pkgconf" --libs sqlite3)
version=$("$pkgconf" --modversion sqlite3)
[ "$version" = "${SQLITE_EXPECT_VERSION:-3.53.4}" ] || {
    echo "Unexpected SQLite version: $version" >&2; exit 1;
}
{
    uname -a
    "${CC:-cc}" --version
    "$pkgconf" --modversion sqlite3
    "$pkgconf" --cflags --libs sqlite3
} > "$out/environment.txt"
# pkg-config emits compiler words, not arbitrary shell commands.
"${CC:-cc}" -std=c99 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -O2 \
    ${CPPFLAGS:-} ${CFLAGS:-} $cflags "$here/consumer.c" \
    ${LDFLAGS:-} $libs -o "$out/consumer"
case $(uname -s) in
NetBSD|Linux) ldd "$out/consumer" > "$out/linkage.txt" ;;
Darwin) otool -L "$out/consumer" > "$out/linkage.txt" ;;
esac
"$out/consumer" "$out/test.db" > "$out/results.txt"
cat "$out/results.txt"
printf '%s\n' 'Installed SQLite consumer checks passed.' > "$out/SUCCESS"

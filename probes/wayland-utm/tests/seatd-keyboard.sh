#!/bin/sh
# Compile the actual upstream terminal.c with only its ioctl boundary replaced.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh seatd-keyboard.sh PATCHED_SEATD_SOURCE OUTPUT_DIR' >&2; exit 2; }
source=$1
output=$2
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$output"
cc -std=c11 -D_NETBSD_SOURCE -Wall -Wextra -Werror -I"$source/include" \
    -Dioctl=seatd_test_ioctl -c "$source/common/terminal.c" -o "$output/terminal.o"
cc -std=c11 -D_NETBSD_SOURCE -Wall -Wextra -Werror -I"$source/include" \
    "$here/seatd-keyboard.c" "$output/terminal.o" "$source/common/log.c" \
    -o "$output/seatd-keyboard"
"$output/seatd-keyboard"

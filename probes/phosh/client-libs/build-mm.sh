#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 EmberBSD contributors. AI-assisted build probe.
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo 'Usage: sh build-mm.sh NEW_WORK_DIRECTORY [ARCHIVE_DIRECTORY]' >&2
    exit 2
fi
WORK_DIR=$1
export WORK_DIR
shift
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /bin/sh "$script_dir/probe.sh" modemmanager "$@"

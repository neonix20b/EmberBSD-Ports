#!/bin/sh
# SPDX-License-Identifier: MIT
# A disposable native source probe, not a package or system installer.
set -eu
umask 022
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: build.sh ABS_NEW_WORK [ABS_ARCHIVE_CACHE]' >&2; exit 2; }
work=$1
case "$work" in /*) ;; *) echo 'Use an absolute work path.' >&2; exit 2 ;; esac
case "$work" in *[!a-zA-Z0-9_./-]*) echo 'Use a simple work path.' >&2; exit 2 ;; esac
[ ! -e "$work" ] && [ ! -L "$work" ] || { echo 'Work path already exists.' >&2; exit 2; }
if [ "$#" = 2 ]; then
    case "$2" in /*) ;; *) echo 'Use an absolute archive cache.' >&2; exit 2 ;; esac
    [ -d "$2" ] || { echo 'Archive cache is not a directory.' >&2; exit 2; }
fi
jobs=${JOBS:-1}
case "$jobs" in ''|0|*[!0-9]*) echo 'JOBS must be positive.' >&2; exit 2 ;; esac
[ "$jobs" -gt 0 ] 2>/dev/null || { echo 'JOBS must be positive.' >&2; exit 2; }
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
mkdir "$work"
mkdir "$work/src" "$work/archives" "$work/logs"
prefix=$work/install
hash()
{
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1";
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
# Check all archives before extracting any, including cached archives.
while read -r name expected url; do
    if [ "$#" = 2 ]; then
        cp "$2/$name" "$work/archives/$name"
    else
        curl -fLsS --connect-timeout 20 --max-time 900 "$url" -o "$work/archives/$name"
    fi
    actual=$(hash "$work/archives/$name")
    [ "$actual" = "$expected" ] || { echo "Checksum mismatch: $name; nothing extracted." >&2; exit 2; }
    printf '%s %s %s\n' "$name" "$actual" "$url" >> "$work/logs/sources.txt"
done < "$recipe/sources.tsv"
[ "$(uname -s)" = NetBSD ] || { echo 'Native EmberBSD/NetBSD required.' >&2; exit 2; }
CC=${CC:-/usr/bin/cc}
CXX=${CXX:-/usr/bin/c++}
for tool in "$CC" "$CXX" cmake ninja tar; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
export CC CXX
printf '%s\n' "$(command -v "$CXX")" > "$work/logs/cxx.txt"
for archive in "$work"/archives/*.tar.gz; do tar -xzf "$archive" -C "$work/src"; done
{
    uname -a
    "$CC" --version
    "$CXX" --version
    cmake --version
    ninja --version
} > "$work/logs/tools.txt"
run()
{
    stage=$1
    shift
    printf '%s\n' "$stage"
    status=0
    "$@" > "$work/logs/$stage.log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        tail -60 "$work/logs/$stage.log" >&2
        echo "Failed: $stage ($status)" >&2
        exit "$status"
    fi
}
run behaviortree-configure cmake -S "$work/src/BehaviorTree.CPP-4.9.0" -B "$work/behaviortree-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON \
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_ament_cmake=TRUE \
    -DBTCPP_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DBTCPP_BUILD_TOOLS=OFF \
    -DBTCPP_EXAMPLES=OFF -DBTCPP_GROOT_INTERFACE=OFF -DBTCPP_SQLITE_LOGGING=OFF
run behaviortree-build cmake --build "$work/behaviortree-build" --parallel "$jobs"
run behaviortree-install cmake --install "$work/behaviortree-build"
licenses=$prefix/share/behaviortree-probe/licenses
mkdir -p "$licenses"
cp "$recipe/sources.tsv" "$recipe/PROVENANCE.md" "$prefix/share/behaviortree-probe/"
cp "$work/src/BehaviorTree.CPP-4.9.0/LICENSE" "$licenses/BehaviorTree-LICENSE"
for component in minicoro minitrace; do
    cp "$work/src/BehaviorTree.CPP-4.9.0/3rdparty/$component/LICENSE" "$licenses/$component-LICENSE"
done
cp "$work/src/BehaviorTree.CPP-4.9.0/3rdparty/tinyxml2/LICENSE.txt" "$licenses/tinyxml2-LICENSE"
# Preserve supplemental licenses and the original installed header notices.
cp "$work"/archives/*-LICENSE.txt "$licenses/"
echo "Installed in $prefix; run test.sh to verify the installed consumers."

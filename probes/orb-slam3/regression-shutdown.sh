#!/bin/sh
# SPDX-License-Identifier: MIT
# Compare the pinned upstream Shutdown method with the installed adaptation.
set -eu
[ "$#" = 3 ] || { echo 'Usage: regression-shutdown.sh ABS_WORK ABS_COMMON_PREFIX ABS_CACHE' >&2; exit 2; }
work=$1
common=$2
opencv=${OPENCV_PREFIX:-$common}
cache=$3
for directory in "$@" "$opencv"; do
    case "$directory" in /*) ;; *) echo 'Use absolute paths.' >&2; exit 2 ;; esac
    case "$directory" in *[!a-zA-Z0-9_./-]*) echo 'Use simple paths.' >&2; exit 2 ;; esac
done
recipe=$(CDPATH= cd "$(dirname "$0")" && pwd)
archive=$cache/ORB_SLAM3-1.0.tar.gz
if command -v sha256 >/dev/null; then
    actual=$(sha256 -q "$archive")
else
    actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
fi
expected=$(awk '$1 == "ORB_SLAM3-1.0.tar.gz" { print $2 }' "$recipe/sources.tsv")
[ "$actual" = "$expected" ] || { echo 'Source checksum mismatch.' >&2; exit 2; }
baseline=$work/shutdown-baseline
mkdir -p "$baseline"
tar -xOf "$archive" ORB_SLAM3-1.0-release/src/System.cc > "$baseline/System.cc"
# Preserve the original copyright/license and exact original method body.
awk 'NR == 1, /^\*\// { print }' "$baseline/System.cc" > "$baseline/shutdown.cpp"
printf '#include <System.h>\nnamespace ORB_SLAM3 {\n' >> "$baseline/shutdown.cpp"
awk '/^void System::Shutdown\(\)/ { copying=1 } /^bool System::isShutDown/ { copying=0 } copying { print }' \
    "$baseline/System.cc" >> "$baseline/shutdown.cpp"
printf '}\n' >> "$baseline/shutdown.cpp"
# A second mutation restores the inherited stop-before-GBA-tail ordering.
# All scheduling is controlled by the atomic cancellation handshake in the test.
awk 'NR == 1, /^\*\// { print }' "$baseline/System.cc" > "$baseline/stop-order.cpp"
printf '#include <LoopClosing.h>\nnamespace ORB_SLAM3 {\n' >> "$baseline/stop-order.cpp"
awk '/^void LoopClosing::StopLocalMappingForLoop\(\)/ { copying=1 }
     /^void LoopClosing::CorrectLoop\(\)/ { copying=0 }
     copying && /mpLocalMapper->RequestStop\(\);|mpLocalMapper->EmptyQueue\(\);/ { next }
     copying { print; if ($0 == "{" && !inserted) {
         print "    mpLocalMapper->RequestStop();";
         print "    mpLocalMapper->EmptyQueue();"; inserted=1;
     } }' "$work/src/ORB_SLAM3-1.0-release/src/LoopClosing.cc" >> "$baseline/stop-order.cpp"
printf '}\n' >> "$baseline/stop-order.cpp"
cmake -S "$recipe/tests" -B "$work/test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$work/install" -DCOMMON_PREFIX="$common" \
    -DOPENCV_PREFIX="$opencv" \
    -DUPSTREAM_SHUTDOWN_SOURCE="$baseline/shutdown.cpp" \
    -DWRONG_STOP_ORDER_SOURCE="$baseline/stop-order.cpp" \
    -DCMAKE_BUILD_RPATH="$work/install/lib/orb-slam3;$opencv/lib;$common/lib;/usr/pkg/lib" \
    > "$work/logs/baseline-configure.log" 2>&1
cmake --build "$work/test-build" --parallel 1 > "$work/logs/baseline-build.log" 2>&1
result=0
LD_PRELOAD="$work/test-build/libupstream-shutdown.so" \
    ctest --test-dir "$work/test-build" -R '^orb-shutdown$' --verbose \
    > "$work/logs/baseline-red.log" 2>&1 || result=$?
cat "$work/logs/baseline-red.log"
[ "$result" != 0 ] && grep -F 'Shutdown returned with native worker threads alive' \
    "$work/logs/baseline-red.log" >/dev/null || {
    echo 'The pinned upstream method did not reproduce the shutdown failure.' >&2; exit 1;
}
ctest --test-dir "$work/test-build" -R '^orb-shutdown$' --verbose \
    > "$work/logs/baseline-green.log" 2>&1
cat "$work/logs/baseline-green.log"
echo 'PASS: original Shutdown fails; installed adaptation passes.'
result=0
LD_PRELOAD="$work/test-build/libwrong-stop-order.so" \
    ctest --test-dir "$work/test-build" -R '^orb-gba-stop-order$' --verbose \
    > "$work/logs/stop-order-red.log" 2>&1 || result=$?
cat "$work/logs/stop-order-red.log"
[ "$result" != 0 ] && grep -F 'finishing GBA erased the loop correction stop request' \
    "$work/logs/stop-order-red.log" >/dev/null || {
    echo 'The inherited wrong stop order did not reproduce the lost request.' >&2; exit 1;
}
ctest --test-dir "$work/test-build" -R '^orb-gba-stop-order$' --verbose \
    > "$work/logs/stop-order-green.log" 2>&1
cat "$work/logs/stop-order-green.log"
echo 'PASS: inherited stop ordering fails; installed adaptation passes.'
# Restore the two inherited missing-pose history operations. In the original
# OK/RECENTLY_LOST outer branch, (mState == LOST) was necessarily false.
mkdir -p "$baseline/legacy-history"
sed -e 's/timestamps.push_back(current_timestamp);/timestamps.push_back(timestamps.back());/' \
    -e 's/lost.push_back(true);/lost.push_back(false);/' \
    "$work/install/include/ORB_SLAM3/include/TrackingHistory.h" \
    > "$baseline/legacy-history/TrackingHistory.h"
cmake -S "$recipe/tests" -B "$work/history-test-build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPROBE_PREFIX="$work/install" -DCOMMON_PREFIX="$common" \
    -DOPENCV_PREFIX="$opencv" -DLEGACY_HISTORY_INCLUDE="$baseline/legacy-history" \
    -DCMAKE_BUILD_RPATH="$work/install/lib/orb-slam3;$opencv/lib;$common/lib;/usr/pkg/lib" \
    > "$work/logs/history-configure.log" 2>&1
cmake --build "$work/history-test-build" --parallel 1 > "$work/logs/history-build.log" 2>&1
result=0
ctest --test-dir "$work/history-test-build" -R '^orb-unavailable-pose$' --verbose \
    > "$work/logs/history-red.log" 2>&1 || result=$?
cat "$work/logs/history-red.log"
[ "$result" != 0 ] && grep -F 'unavailable pose repeated an old timestamp or claimed tracking success' \
    "$work/logs/history-red.log" >/dev/null || {
    echo 'The inherited unavailable-pose history did not reproduce the failure.' >&2; exit 1;
}
ctest --test-dir "$work/test-build" -R '^orb-unavailable-pose$' --verbose \
    > "$work/logs/history-green.log" 2>&1
cat "$work/logs/history-green.log"
echo 'PASS: inherited unavailable-pose history fails; actual production helper passes.'

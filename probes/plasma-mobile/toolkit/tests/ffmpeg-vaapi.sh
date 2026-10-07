#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD; AI-assisted regression for the Qt FFmpeg CMake branch.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 QT_MULTIMEDIA_SOURCE NEW_WORK" >&2; exit 2; }
source=$(CDPATH= cd -- "$1" && pwd)
mkdir "$2"
work=$(CDPATH= cd -- "$2" && pwd)
# Execute the production VAAPI branch. Target creation is recorded below;
# this tests conditional linkage, not native library availability or playback.
sed -n '/^if (QT_FEATURE_vaapi)/,/^qt_internal_extend_target.*APPLE/{
    /^qt_internal_extend_target.*APPLE/!p
}' "$source/src/plugins/multimedia/ffmpeg/CMakeLists.txt" > "$work/vaapi.cmake"
test -s "$work/vaapi.cmake"
cat > "$work/check.cmake" <<'CMAKE'
set(QT_FEATURE_vaapi TRUE)
set(QT_LINK_STUBS_TO_FFMPEG_PLUGIN FALSE)
set(FFMPEG_SHARED_LIBRARIES TRUE)
set(direct_link FALSE)
set(private_stub FALSE)
function(qt_internal_extend_target target)
    if ("${ARGN}" MATCHES "VAAPI::VAAPI")
        set(direct_link TRUE PARENT_SCOPE)
    endif()
endfunction()
function(target_compile_definitions)
endfunction()
if (LINUX OR ANDROID)
    function(qt_internal_multimedia_find_vaapi_soversion)
    endfunction()
    function(qt_internal_multimedia_add_private_stub_to_plugin name)
        if (NOT name STREQUAL "va")
            message(FATAL_ERROR "Unexpected stub")
        endif()
        set(private_stub TRUE PARENT_SCOPE)
    endfunction()
endif()
include("${CMAKE_CURRENT_LIST_DIR}/vaapi.cmake")
if (NOT "${direct_link}" STREQUAL "${EXPECT_DIRECT}")
    message(FATAL_ERROR "Wrong direct-link selection: ${direct_link}")
endif()
if (NOT "${private_stub}" STREQUAL "${EXPECT_STUB}")
    message(FATAL_ERROR "Wrong private-stub selection: ${private_stub}")
endif()
CMAKE
cmake=${CMAKE:-cmake}
for platform in netbsd linux android; do
    linux=FALSE android=FALSE
    case "$platform" in linux) linux=TRUE ;; android) android=TRUE ;; esac
    for stubs in none va; do
        direct=TRUE stub=FALSE
        if [ "$stubs" = va ] && [ "$platform" != netbsd ]; then direct=FALSE; stub=TRUE; fi
        "$cmake" -DLINUX="$linux" -DANDROID="$android" -DFFMPEG_STUBS="$stubs" \
            -DEXPECT_DIRECT="$direct" -DEXPECT_STUB="$stub" \
            -P "$work/check.cmake" > "$work/$platform-$stubs.log" 2>&1 || {
            cat "$work/$platform-$stubs.log" >&2; exit 1;
        }
    done
done
echo 'PASS: six production VAAPI linkage branches; native multimedia remains pending'

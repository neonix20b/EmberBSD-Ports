#!/bin/sh
# Origin: EmberBSD; AI-assisted staged graphics ABI audit.
set -eu
[ "$#" -ge 4 ] || { echo 'Usage: sh audit-libraries.sh GRAPHICS_PREFIX LLVM_LIBDIR CXX_LIBDIR INPUT_PREFIX [CONSUMER ...]' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD loader audit required.' >&2; exit 2; }
prefix=$1
llvm=$2
cxx=$3
input=$4
shift 4
for path in "$prefix" "$llvm" "$cxx" "$input"; do
    case "$path" in /*) ;; *) echo 'Absolute prefixes required.' >&2; exit 2 ;; esac
done
# Supply affected Qt/GNOME/Xorg consumers as further paths when considering
# shared-stack promotion. Their absence here never establishes acceptance.
set -- "$prefix/lib/libEGL.so" "$prefix/lib/libGL.so" \
    "$prefix/lib/libGLESv1_CM.so" "$prefix/lib/libGLESv2.so" \
    "$prefix/lib/libgbm.so" "$prefix/lib/libgallium-26.2.4.so" "$@"
for object do
    [ -f "$object" ] || { echo "Missing artifact: $object" >&2; exit 1; }
    printf '\nArtifact: %s\n' "$object"
    sha256 "$object"
    readelf -d "$object"
    loaded=$(ldd "$object")
    printf '%s\n' "$loaded"
    if printf '%s\n' "$loaded" | grep -E 'not found|libglapi\.so'; then
        echo 'Unresolved or legacy shared-glapi dependency.' >&2
        exit 1
    fi
    paths=$(printf '%s\n' "$loaded" | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p')
    [ -n "$paths" ] || { echo 'No native loader paths found.' >&2; exit 1; }
    printf '%s\n' "$paths" | while IFS= read -r path; do
        name=${path##*/}
        case "$name" in
            libEGL.so*|libGL.so*|libGLES*.so*|libgbm.so*|libgallium*.so*|libdrm.so*)
                expected=$prefix/lib ;;
            libLLVM*.so*) expected=$llvm ;;
            libstdc++.so*|libgcc_s.so*) expected=$cxx ;;
            libinput.so*) expected=$input/lib ;;
            *) continue ;;
        esac
        case "$path" in "$expected"/*) ;; *)
            printf 'Mixed dependency: %s; expected under %s\n' "$path" "$expected" >&2
            exit 1 ;;
        esac
    done
    if [ "$object" = "$prefix/lib/libgallium-26.2.4.so" ]; then
        printf '%s\n' "$paths" | grep -F "$llvm/libLLVM" >/dev/null
        printf '%s\n' "$paths" | grep -F "$cxx/libstdc++" >/dev/null
    fi
    case "$object" in
        "$prefix/lib/libEGL.so"|"$prefix/lib/libGL.so"|"$prefix/lib/libgallium-26.2.4.so")
            symbols=$(nm -g "$object")
            if printf '%s\n' "$symbols" | grep -E ' (U|T|D|B|W) (util_atexit|__dso_handle)$'; then
                echo 'DSO cleanup binding is not owner-local.' >&2
                exit 1
            fi ;;
    esac
done
echo 'Staged library paths and ABI dependencies: PASS (not runtime/promotion acceptance)'

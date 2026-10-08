#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), bounded installed guest VirGL draw acceptance.
# Reuses the accepted, unchanged epoxy-render and package verifiers.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
hash() {
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

verify_bundle() {
    vb_directory=$1
    vb_digest=$2
    [ "$(hash "$vb_directory/artifacts.sha256")" = "$vb_digest" ] || fail 'Unaccepted bundle manifest'
    while read -r vb_expected vb_file; do
        [ -f "$vb_directory/$vb_file" ] && [ ! -L "$vb_directory/$vb_file" ] &&
            [ "$(hash "$vb_directory/$vb_file")" = "$vb_expected" ] || fail "Bundle drift: $vb_file"
    done < "$vb_directory/artifacts.sha256"
    # The pinned manifest contains only simple relative paths. Also reject
    # unrecorded files, directory symlinks and special files, including dotfiles.
    vb_special=$(find "$vb_directory" ! -type d ! -type f -print) || fail 'Bundle inventory failed'
    [ -z "$vb_special" ] || fail 'Nonregular bundle artifact'
    vb_inventory=$(cd "$vb_directory" && find . -type f -print) || fail 'Bundle inventory failed'
    printf '%s\n' "$vb_inventory" | awk '
        NR == FNR { expected[$2] = 1; next }
        { sub(/^\.\//, ""); if ($0 != "artifacts.sha256" && !($0 in expected)) bad=1 }
        END { exit bad }
    ' "$vb_directory/artifacts.sha256" - || fail 'Unrecorded bundle artifact'
}

verify_inputs() {
    verify_bundle "$mesa" b52449225ae5f9a204a7ad1e03eba16e9de37ec844c97bc9909326806533fbf0
    verify_bundle "$epoxy" 906215cfd3b9b10580181fd3ea13ef2fe7a82c52cc668302b612e8b5c4f75605
    # Execute only verifier scripts whose bytes were just checked against the
    # accepted manifests. They check full package files/links and runtime DSOs.
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/sh "$mesa/run-mesa-package-tests.sh" \
        --verify-sysroot "$mesa" "$root"
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin /bin/sh "$epoxy/run-epoxy-tests.sh" \
        --verify-sysroot "$epoxy" "$root"
}

check_overrides() {
    for setting in LD_LIBRARY_PATH LD_PRELOAD LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH \
        MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER; do
        eval "value=\${$setting-}"
        [ -z "$value" ] || fail "Runtime override is not permitted: $setting"
    done
}

recorded_library() {
    provider=$1
    case "$provider" in
        */../*|*/..|*/./*|*' '*) fail "Invalid library path: $provider";;
        /usr/pkg/*)
            provider_directory=$(CDPATH= cd -- "$(dirname -- "$root$provider")" && pwd -P)
            provider_path=$provider_directory/$(basename -- "$provider")
            # root is / in target execution; a private sysroot is used only by
            # the source-body guard fixture, never by the rendering command.
            if [ "$root" = / ]; then recorded=$provider_path
            else recorded=${provider_path#"$root"}; fi
            expected=$(awk -v path="$recorded" '$2 == path { print $1 }' "$epoxy/runtime-libraries.sha256")
            [ "${#expected}" = 64 ] && [ "$(hash "$provider_path")" = "$expected" ] ||
                fail "Unrecorded or changed package library: $provider";;
        /usr/lib/*|/lib/*|/libexec/ld.elf_so|/usr/libexec/ld.elf_so) ;;
        *) fail "Foreign library: $provider";;
    esac
}

check_render_log() {
    awk '
        /^Cycle / {
            n++;
            if ($0 !~ /^Cycle [1-4]: EGL [0-9.]+; GL .*; renderer virgl/ || $2 != n ":") bad=1
        }
        /^PASS: shader rejection, clear, triangle pixels and four EGL lifecycles$/ { passed++ }
        END { exit (bad || n != 4 || passed != 1) }
    ' "$logs/epoxy-render.log" || fail 'Missing four VirGL draw cycles'
    while read -r dependency; do recorded_library "$dependency"; done <<EOF
$(sed -n 's/^LOADED: //p' "$logs/epoxy-render.log")
EOF
    for provider_name in libepoxy.so libEGL.so libGLESv2.so libgbm.so libgallium-26.2.4.so libLLVM.so libdrm.so; do
        awk -v name="$provider_name" 'index($0, "LOADED: /usr/pkg/lib/" name) == 1 { found=1 } END { exit !found }' \
            "$logs/epoxy-render.log" ||
            fail "Missing live provider: $provider_name"
    done
}

run_draw() {
    result=0
    env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/pkg/bin MESA_SHADER_CACHE_DISABLE=true \
        "$timeout" -k 5 60 "$epoxy/bin/epoxy-render" /dev/dri/renderD128 virgl \
        > "$logs/epoxy-render.log" 2>&1 || result=$?
    printf '%s\n' "$result" > "$logs/exit-status"
    [ "$result" = 0 ] || return "$result"
    check_render_log
}

main() {
    mode=run
    if [ "$#" = 4 ] && [ "$1" = --verify-sysroot ]; then
        mode=verify
        shift
    elif [ "$#" != 3 ]; then
        echo 'Usage: run-virgl-draw.sh MESA_BUNDLE EPOXY_BUNDLE NEW_LOG_DIRECTORY' >&2
        echo '       run-virgl-draw.sh --verify-sysroot MESA_BUNDLE EPOXY_BUNDLE SYSROOT' >&2
        exit 2
    fi
    for path in "$@"; do case "$path" in /*) ;; *) fail 'Absolute paths required';; esac; done
    mesa=$(CDPATH= cd -- "$1" && pwd -P)
    epoxy=$(CDPATH= cd -- "$2" && pwd -P)
    root=/
    if [ "$mode" = verify ]; then root=$(CDPATH= cd -- "$3" && pwd -P); fi
    check_overrides
    verify_inputs
    if [ "$mode" = verify ]; then
        echo 'PASS: accepted bundle and installed input guards only; no rendering'
        return
    fi
    [ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || fail 'NetBSD/AArch64 required'
    [ -c /dev/dri/renderD128 ] && [ ! -L /dev/dri/renderD128 ] || fail 'Native renderD128 device required'
    timeout=/usr/bin/timeout
    [ -x "$timeout" ] || fail 'Native /usr/bin/timeout required'
    mkdir "$3"
    logs=$(CDPATH= cd -- "$3" && pwd -P)
    uname -a > "$logs/platform.log"
    printf '%s  %s\n' "$(hash "$mesa/artifacts.sha256")" "$mesa/artifacts.sha256" \
        "$(hash "$epoxy/artifacts.sha256")" "$epoxy/artifacts.sha256" \
        "$(hash "$0")" "$0" > "$logs/inputs.sha256"
    ldd "$epoxy/bin/epoxy-render" > "$logs/epoxy-render.ldd.log" 2>&1
    awk '$2 == "=>" && $3 !~ /^\// { bad=1 } END { exit bad }' "$logs/epoxy-render.ldd.log" || fail 'Unresolved dependency'
    while read -r dependency; do recorded_library "$dependency"; done <<EOF
$(awk '$2 == "=>" { print $3 }' "$logs/epoxy-render.ldd.log")
EOF
    run_draw
    echo 'PASS: installed VirGL shader/triangle readback and four GBM EGL lifecycles on renderD128'
}

main "$@"

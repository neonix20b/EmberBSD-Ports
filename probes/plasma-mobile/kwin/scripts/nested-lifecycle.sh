# SPDX-License-Identifier: MIT
# Shared lifecycle operations for the nested contract and its regression test.

prepare_profile()
{
    mkdir -p "$build_root/contract"
    run=$(mktemp -d "$build_root/contract/run.XXXXXX")
    XDG_RUNTIME_DIR=$run/runtime
    XDG_CONFIG_HOME=$run/config
    XDG_CACHE_HOME=$run/cache
    XDG_DATA_HOME=$run/data
    export XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    mkdir -m 700 "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
    unset DBUS_SESSION_BUS_ADDRESS DBUS_STARTER_ADDRESS DBUS_STARTER_BUS_TYPE
    unset WAYLAND_SOCKET XAUTHORITY
    # No includes or service directories: this bus cannot activate helpers.
    cat >"$run/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$XDG_RUNTIME_DIR/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="$(id -u)"/>
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
EOF
}

child_exited()
{
    child_count=0
    while kill -0 "$1" 2>/dev/null; do
        [ "$child_count" -lt "$2" ] || return 1
        sleep 1
        child_count=$((child_count + 1))
    done
}

stop_owned()
{
    owned_pid=$1
    owned_name=$2
    [ -n "$owned_pid" ] || return 0
    kill -TERM "$owned_pid" 2>/dev/null || :
    if ! child_exited "$owned_pid" 5; then
        echo "forced=$owned_name:$owned_pid" >>"$run/cleanup.txt"
        kill -KILL "$owned_pid" 2>/dev/null || :
        if ! child_exited "$owned_pid" 2; then
            echo "Owned $owned_name child $owned_pid survived KILL." >&2
            echo "remaining=$owned_name:$owned_pid" >>"$run/cleanup.txt"
            return 1
        fi
    fi
    # Only wait after the direct child is proven absent; never block after KILL.
    wait "$owned_pid" 2>/dev/null || :
    echo "reaped=$owned_name:$owned_pid" >>"$run/cleanup.txt"
}

cleanup()
{
    cleanup_error=0
    stop_owned "$client_pid" client || cleanup_error=1
    kwin_stopped=false
    if stop_owned "$kwin_pid" kwin; then kwin_stopped=true; else cleanup_error=1; fi
    x_stopped=false
    if stop_owned "$x_pid" xvfb; then x_stopped=true; else cleanup_error=1; fi
    bus_stopped=false
    if stop_owned "$bus_pid" dbus; then bus_stopped=true; else cleanup_error=1; fi

    # This directory was created privately for this run. Remove stale private
    # nodes only after their owning direct child has exited.
    if [ "$kwin_stopped" = true ]; then
        rm -f "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock" || cleanup_error=1
    fi
    if [ "$bus_stopped" = true ]; then
        rm -f "$XDG_RUNTIME_DIR/bus" || cleanup_error=1
    fi
    if [ -n "$x_pid" ]; then
        # A killed X server cannot unlink its nodes. The lock must still name
        # our exited child; never remove a foreign or unidentifiable socket.
        if [ "$x_stopped" = true ] && [ -f "$x_lock" ] &&
           [ "$(tr -d '[:space:]' <"$x_lock")" = "$x_pid" ]; then
            rm -f "$x_socket" "$x_lock" || cleanup_error=1
        fi
        for node in "$x_socket" "$x_lock"; do
            if [ -e "$node" ] || [ -L "$node" ]; then
                echo "X11 node remains: $node" >&2
                cleanup_error=1
            fi
        done
    fi
    for node in "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock" "$XDG_RUNTIME_DIR/bus"; do
        if [ -e "$node" ] || [ -L "$node" ]; then
            echo "Private session node remains: $node" >&2
            cleanup_error=1
        fi
    done
    # Preserve the display reservation if cleanup could not be confirmed.
    if [ "$cleanup_error" -eq 0 ] && [ -n "$display_guard" ]; then
        rmdir "$display_guard" || cleanup_error=1
    fi
    echo "cleanup_status=$cleanup_error" >>"$run/cleanup.txt"
    return "$cleanup_error"
}

finish()
{
    finish_status=$?
    trap - EXIT
    trap '' HUP INT TERM
    cleanup || { [ "$finish_status" -ne 0 ] || finish_status=1; }
    if [ "$finish_status" -eq 0 ] && [ "$contract_complete" = true ]; then
        echo "PASS: native Wayland drawing, nested input and cleanup; evidence: $run"
    fi
    exit "$finish_status"
}

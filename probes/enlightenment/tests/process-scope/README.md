# Scoped Enlightenment process cleanup for NetBSD

`session-processes` finds cooperative session processes even after `setsid()` or
reparenting. By default, it matches the complete NUL-delimited environment token
`EMBERBSD_ENLIGHTENMENT_SESSION=<absolute session directory>` from its own environment.
It never matches command text, a process name, a process group or every process of a UID.
This is new, AI-assisted EmberBSD code under BSD-2-Clause; see
`../../LICENSES/EMBERBSD-HELPERS`.

Another desktop launcher can set the marker at compile time, for example
`'-DMARKER="EMBERBSD_PLASMA_SESSION"'`. The default Enlightenment marker and
all process-identity checks stay unchanged. The shared
[marker regression](../../../plasma-mobile/scripts/test-process-marker.sh)
runs the existing native scope and cancellation checks for both names:

```sh
sh /absolute/path/to/probes/plasma-mobile/scripts/test-process-marker.sh \
    "$HOME/.cache/plasma-marker-regression"
```

Use a new directory and an ordinary NetBSD user. Both marker variants passed
on NetBSD 11/aarch64; evidence directories are retained by the test.

Build on NetBSD in a new disposable directory:

```sh
recipe=/absolute/path/to/probes/enlightenment
scope_work="$HOME/.cache/enlightenment-process-tests"
mkdir "$scope_work"
cp "$recipe/tests/process-scope/test-session-processes.sh" \
    "$recipe/tests/process-scope/test-cancellation.sh" "$scope_work/"
cd "$scope_work"
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror -O2 \
    "$recipe/session-processes.c" -o session-processes
```

Export a fresh `mktemp -d` session path before launching the private D-Bus session and
its applications. Keep that directory until all cleanup passes finish. The directory
must belong to the caller, must be absolute and must not be group/other writable.
The helper refuses root or mismatched real/effective UID or GID. Targets must have
matching real, effective and saved UID, and valid process start-time data. The helper
and its direct parent are always excluded.

```sh
export EMBERBSD_ENLIGHTENMENT_SESSION="$session_dir"
# Launch the private session with this environment already present.
# Later, invoke the helper directly from its controlling shell:
"$helper" --signal TERM > "$session_dir/term-pids"
"$helper" --check > "$session_dir/remaining-pids"
"$helper" --signal KILL > "$session_dir/kill-pids"
```

The launcher should implement bounded TERM/wait/KILL/check loops. Each invocation
performs a fresh process enumeration; do not cache its PID output for later signaling.
The marker must also be propagated to a private D-Bus activation environment when
activation changes that environment. Invoke the helper directly from the controlling
shell, rather than through another marked shell: only the direct parent is exempt.

| Exit status | Meaning |
| --- | --- |
| 0 | At least one matching process found (`--check`) or successfully signaled. |
| 1 | No matching live process found or successfully signaled. |
| 2 | Invalid invocation, unsafe caller/directory, or incomplete scan/signal error. |

Standard output contains only matching or signaled PIDs, one per line. Diagnostics
contain no environment contents. Status 2 must never be treated as proof of cleanup.
Signaling success does not prove that the process exited; follow it with `--check`.
Expected process disappearance during enumeration is harmless.

The helper uses `KERN_PROC2` followed by `KERN_PROC_ARGS/KERN_PROC_ENV`. It checks
PID, UID and start timestamp before reading the environment and again immediately
before signaling. Process-table growth retries and memory consumption are bounded.
Environment reads at their buffer limit are retried with a larger buffer because
NetBSD can report successful truncation. A 16 MiB environment limit or other unreadable
same-UID environment makes the scan incomplete, without targeting that process.

This is a cleanup contract for cooperative applications, not a security sandbox.
An application can clear or rewrite its environment. A same-UID process can copy
the token. Separate identity checks and `kill(2)` cannot make PID reuse or concurrent
credential/environment changes atomic. Callers must keep cleanup bounded and report
remaining or uninspectable processes. The helper provides no root capability.

## Native integration checks

```sh
cc -std=c99 -D_NETBSD_SOURCE -Wall -Wextra -Werror -O2 \
    "$recipe/tests/process-scope/scope-child.c" -o scope-child
sh test-session-processes.sh
sh test-cancellation.sh
```

Run as a non-root user in an isolated writable directory. Test fixtures expire after
60 seconds as a final bound. Shell traps clean the exact test markers and the test's
own unreaped untagged child. No X server or graphical session is needed or touched.
The tests cover ordinary children, an actual orphan with its own session/process group,
a TERM-resistant child, exact value boundaries using another marker with the same
prefix, an untagged sentinel, fresh enumeration after a new child starts, and TERM
cancellation of the test controller. Test evidence directories are retained.

Verified on NetBSD 11.0/aarch64 as an ordinary UID: both integration tests passed;
compilation used all flags above. GUI lifecycle integration remains the launcher's
separate test. No security-boundary claim follows from these tests.

ABI references: native `/usr/include/sys/sysctl.h` revision 1.241 (2025-07-13), native
`sysctl(7)`, [NetBSD sysctl(7)](https://man.netbsd.org/sysctl.7), and
[NetBSD 11 kern_proc.c](https://github.com/NetBSD/src/blob/netbsd-11/sys/kern/kern_proc.c)
(`sysctl_doeproc`, `sysctl_kern_proc_args`, `copy_procargs`, `fill_kproc2`).

The real graphical launcher has an additional integration regression:

```sh
sh "$recipe/tests/process-scope/test-launcher-cancellation.sh" "$recipe" \
    "$HOME/.cache/emberbsd-enlightenment"
```

It reserves display 80, checks Enlightenment's actual WM identity, stops
its own Xvfb with SIGSTOP, and cancels the launcher while an Xlib request
is blocked. A tagged setsid orphan ignores TERM; an untagged sentinel
must survive. The test checks status 143 within twelve seconds, empty
scope, stopped X server and absence of its X lock/socket/reservation.
The final native run returned 143 in two seconds. This is a cancellation
bound observed on the test VM, not a hard real-time guarantee.

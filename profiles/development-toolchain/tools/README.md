# Bounded native GCC build

`native-build-guard.c` is a small supervisor for this profile's long native
package build. It is not installed as a service. Compile it with the base C
compiler (`cc -std=c11 -Wall -Wextra -Werror -O2`). Run its shell regression
checks on the intended scratch filesystem before using it for GCC.

```sh
sh test-native-build-guard.sh /absolute/guard /scratch/new-tests /scratch
mkdir /scratch/new-gcc-run
/absolute/guard /scratch/new-gcc-run /scratch 1048576 2097152 -- \
    /usr/bin/time -l /usr/bin/make -C /scratch/pkgsrc/lang/gcc16 \
    MAKECONF=/scratch/private.mk.conf MAKE_JOBS=1 package
```

Use the actual private paths, preserve a committed source identity, verify
`mount` reports the intended scratch device, and check host free space before
launch. Drain other heavy jobs and arrange explicit monitoring before detaching
with `nohup`. Standard input must be `/dev/null`. Package build does not install
or activate the compiler. Never reuse a run directory.

The guard rejects scratch on the root filesystem and logs available root and
scratch KiB every five seconds. It reserves at least 1 GiB on root and 2 GiB on
scratch, including the other workload's 1 GiB allowance. These are sampled
limits, not filesystem quotas. It does not measure host free space or enforce
a memory limit; the operator must monitor those separately.

`supervisor.pid` identifies the guard; `child.pgid` identifies its child session.
The child creates its own session and confirms that before any group signal.
On a signal or reserve/mount failure, only that group receives TERM and then
KILL after five seconds. The leader stays unreaped until the last signal, so
its process-group identity cannot be reused during cleanup. Commands must not
daemonize or escape their process group. Use TERM on the verified supervisor
identity to cancel; never issue a kill from a stale PID file alone.

`build.log` contains combined output and resource records. `status` is empty
while running and contains a single exit code after completion. Exactly `0`
means package-command success; any nonzero code is failure. Reserved errors are
64 (arguments), 74 (supervisor I/O/setup), 75 (mount/reserve), 126 (session),
127 (exec), or 128+signal. Missing/empty status with a dead supervisor is an
interrupted or failed run, never success. Existing files are refused rather
than overwritten; SIGKILL, machine failure or full-disk I/O may prevent a final
status. Match live process command/start identity and log progress when taking
over monitoring; PID existence by itself is insufficient.

# BehaviorTree.CPP source probe

BehaviorTree.CPP coordinates asynchronous application actions using behavior
trees. This source probe installs current stable 4.9.0 and builds an independent
C++17 application from the installed CMake package. EmberBSD Ports owns the
build recipe and bounded consumer contracts.

The AArch64 EmberBSD VM build passed all six installed-consumer cases on
2026-10-07 with GCC 12.5.0. [Native evidence](NATIVE.md) records the checks,
runtime linkage, source guards, license receipts and validation limits.

## Build and test

The target is native EmberBSD/NetBSD with C++17, CMake, Ninja, curl, tar and
SHA256 support. `CC` and `CXX` default to the base compilers; override them as a
coherent pair if needed. `JOBS` defaults to 1. The absolute work path must be
new and its parent must exist. Existing and failed work paths are preserved.

```sh
sh probes/behaviortree/build.sh /var/tmp/behaviortree-probe
sh probes/behaviortree/test.sh /var/tmp/behaviortree-probe
```

An optional second argument to `build.sh` is an absolute cache containing all
files in [sources.tsv](sources.tsv), including license texts. Every checksum is
checked before any extraction. Installation stays under `WORK/install` and
logs under `WORK/logs`. A test run uses a new `WORK/test-build`; preserve or move
that directory before deliberately rerunning the consumer build.

This standalone profile excludes ROS/ament, upstream tutorials and test builds,
the optional SQLite logger, and the ZeroMQ/Groot interface. It retains XML
parsing, blackboards, control/decorator nodes, asynchronous actions and the
FileLogger2 transition logger. It introduces no SQLite dependency or separate
middleware service. The release's private bundled components are documented in
[PROVENANCE.md](PROVENANCE.md). No Python build step is used.

## Contract and limits

Six installed-consumer cases exercise:

- A real background request: initial `RUNNING`, eventual `SUCCESS`, blackboard
  output, sequence continuation and a second run after state reset.
- Asynchronous `FAILURE`, sequence short-circuit and restart.
- Explicit cancellation, interruptible worker cleanup, no stale output, all
  node states reset to `IDLE`, and cancellation after a fresh restart.
- The built-in `Timeout` decorator cancelling a slow request and returning
  failure before the original operation's delay expires.
- Malformed XML, unknown node names, structurally invalid trees, invalid input
  conversion and missing blackboard values, with no worker started.
- A binary transition log containing the tree, timestamps and the action's
  `RUNNING` then `SUCCESS` transitions. The reader verifies signature, protocol,
  lengths and transition structure. The logger flush method is not a queue
  barrier; a bounded wait observes its writer before logger destruction.

Actions join every worker before cleanup. Polling is bounded to two seconds;
CTest provides a 15-second outer timeout. Generated log files are removed.
The native runner verifies the installed library path and that its libstdc++
matches the recorded compiler. Portable source guards are available separately:

```sh
sh probes/behaviortree/tests/build-guards.sh /var/tmp
```

They reject existing work, zero jobs and corrupt sources before extraction.
This is a source probe rather than a pkgsrc package or a complete robot.
Hardware, hard-real-time behavior,
Groot/ZeroMQ and SQLite logging, ROS integration, and the full upstream test
suite are outside this evidence.

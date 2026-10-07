# Robotics and automotive developer tools

These independent source probes extend EmberBSD's existing vision, inference,
media and Zenoh/ROS 2 tools. They provide C/C++ libraries and installed-consumer
checks for recording experiments, locating visual markers, decoding vehicle
signals, diagnostic exchanges, calibration, behavior logic and device protocols.

| Component | Selected release | Developer workflow |
|---|---|---|
| [MCAP](../mcap/README.md) | C++ 2.1.3 | Record and read timestamped messages, schemas and channels, with optional LZ4/Zstd compression |
| [AprilTag](../apriltag/README.md) | 3.4.5 | Detect known visual markers and estimate their pose |
| [dbcppp](../dbcppp/README.md) | 3.2.6 | Parse DBC and convert CAN payload fields into physical values |
| [iso14229](../iso14229/README.md) | 0.11.0 | Run UDS client/server exchanges over user-space ISO-TP |
| [Ceres Solver](../ceres/README.md) | 2.2.0 | Fit nonlinear models and check solver outcomes |
| [BehaviorTree.CPP](../behaviortree/README.md) | 4.9.0 | Execute asynchronous behavior trees, cancel actions and record transitions |
| [libmodbus](../libmodbus/README.md) | 3.2.0 | Communicate over Modbus TCP and RTU |

Each linked probe owns its source manifest, original licenses, local adaptations,
build instructions, consumer tests and validation boundaries. A release's age
alone does not make it obsolete: the selected version must be the current stable
release or a documented supported choice. No source archive or build product is
stored in this repository.

## Build and consume

Follow the selected component's README for its prerequisites. Each probe accepts
a new absolute work directory and an optional verified source cache:

```sh
export PATH=/usr/pkg/bin:/usr/pkg/sbin:/usr/bin:/usr/sbin:/bin:/sbin
sh probes/COMPONENT/build.sh /absolute/new-work /absolute/source-cache
sh probes/COMPONENT/test.sh /absolute/new-work
```

Replace `COMPONENT` with one directory from the table. Omit the cache argument
to download from the pinned upstream locations. Builds reject an existing work
directory and verify archive hashes before extraction. Use one build job on
small machines. Tests compile against the installed headers/libraries and report
the selected runtime linkage, rather than reusing upstream build-tree targets.

The separate prefixes are disposable validation installations. They are not
per-application permanent dependency stacks. Integrators should use one selected
version of each shared dependency and a coherent C++ runtime for their application.
The probes preserve dependency versions and provenance for that integration.

## Native validation

All seven profiles built and passed their installed-consumer workflows on
2026-10-07 in a dedicated AArch64 VM: EmberBSD EMBER64, NetBSD 11.0 userland,
one vCPU, 3 GiB RAM and base GCC/G++ 12.5.0 with its matching libstdc++.
This compiler is the tested image baseline, not a restriction against later
coherent toolchains. Builds ran sequentially with one job.

There are 19 passing application cases: MCAP 3, AprilTag 2, dbcppp 2,
iso14229 1, Ceres 3, BehaviorTree.CPP 6 and libmodbus 2. They check results
and failure paths, not just successful compilation. Build guards also reject
existing work directories and damaged source archives. Each component records
its exact cases, adaptations, installed-library selection and limits.

Local adaptations address AprilTag ctype arguments, Ceres's Eigen 5 package
request and dbcppp's DBC-only build. iso14229 explicitly selects its included
user-space ISO-TP transport; it does not select Linux CAN_ISOTP sockets.
Upstream authorship and licenses are retained; these changes are not claimed
as accepted upstream. Full upstream suites and binary packaging are separate
from these bounded application checks.

## Scope

These are source profiles, not a published pkgsrc package set or a hardware
support declaration. Numerical fixtures, synthetic images, in-memory CAN frames,
loopback TCP and pseudo-terminal serial links establish software behavior.
They do not establish a physical camera, CAN/CAN FD adapter, RS-485 direction
control, ECU, industrial device, hard real-time deadline or sustained operation.

Use [robotics foundations](../robotics-foundations/README.md) for OpenCV/Eigen/gpsd,
[media](../media/README.md) for file-based videoio, and
[AI engines](../ai-engines/README.md) for CPU inference and speech processing.
The [Zenoh/ROS 2 example](https://github.com/neonix20b/EmberBSD-Examples/tree/main/robotics/zenoh-ros2)
owns cross-device telemetry and command exchange.

# Native BehaviorTree.CPP validation

Validated on 2026-10-07 in an AArch64 EmberBSD VM: NetBSD 11.0 userland,
`EMBER64` kernel, one virtual CPU, 3 GiB RAM, GCC/G++ 12.5.0, CMake 4.3.3,
Ninja 1.13.2. This is VM software evidence, not a physical robot validation.

The pinned BehaviorTree.CPP 4.9.0 archive and supplemental license texts were
verified before extraction. The standalone profile built and installed with
`JOBS=1`, without an upstream source patch. Six independently built installed
consumer cases passed in 0.44 seconds:

| Check | Result |
|---|---|
| Asynchronous success | Initial RUNNING, background completion, blackboard answer 42, sequence continuation, reset and repeat |
| Asynchronous failure | FAILURE, sequence short-circuit, no output, reset and repeat |
| Explicit cancellation | Interruptible worker joined, no late answer, all states IDLE; fresh start and second cancellation |
| Built-in Timeout | Slow request halted, tree FAILURE before the request's original one-second delay |
| Malformed/invalid inputs | Broken XML, unknown node, empty control node, invalid conversion and absent blackboard value rejected |
| FileLogger2 | Actual file records the XML tree, timestamps, and RUNNING then SUCCESS; header/protocol/record structure checked |
| Installed library discovery | CMake and runtime loader selected the private installed BehaviorTree library |
| Runtime identity | `/usr/lib/libstdc++.so.9` matched the recorded base compiler's runtime |
| Build source guards | Existing work, zero jobs and corrupt source rejected before extraction |
| Logger cleanup | No transition test log remained after the test |

SHA256 of the installed shared library was
`f035f592b6fd408d46334394ea9fbd5e698082ad96d7c235de101127fd4e0486`.
The consumer executable was
`fab77b48b661f31595f535c74b800c4f6849a97f4549b64489d4699c9b1a887e`.
These identify this validation build, not a cross-toolchain reproducibility
guarantee. Installed license receipts cover the main library, tinyxml2,
minicoro, minitrace and the supplemental FlatBuffers/Boost/JSON texts.

An Apple Clang 21 host build also passed all six consumers before the native
run. The native run establishes the EmberBSD result. It excludes the full
upstream suite, physical actuators, long-duration behavior, hard real time,
ROS integration, ZeroMQ/Groot connections and SQLite logging.
Source origins and license details are in [PROVENANCE.md](PROVENANCE.md).

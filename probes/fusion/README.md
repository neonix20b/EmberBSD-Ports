# Fusion 1.3.3 native C source profile

This profile supplies an installed C orientation-estimation library for
applications processing gyroscope, accelerometer and magnetometer samples.
[Fusion](https://github.com/xioTechnologies/Fusion/tree/v1.3.3) owns the sensor
fusion algorithm; EmberBSD Ports owns the reproducible installation and
synthetic consumer checks. It is an experimental source profile, not a pkgsrc
package, sensor driver or hardware-qualified IMU system.

## Build and run

Requirements: a C compiler, CMake 3.16 or newer, Ninja, tar and either
`sha256` or `shasum`. Downloading also requires curl. No Python is needed.
Use a new absolute work directory whose parent exists. Paths must not contain
spaces or shell metacharacters. A cache is optional and contains the exact
archive named in [sources.tsv](sources.tsv).

```sh
JOBS=1 sh probes/fusion/build.sh /absolute/new-work /absolute/source-cache
sh probes/fusion/test.sh /absolute/new-work
```

The build verifies the source hash before extraction. It installs into
`new-work/install`, including original headers, `libFusion`, an exact-version
CMake package and the upstream license. It does not change system packages.
Logs remain in `new-work/logs`; build errors keep their nonzero status.

The native upstream CMake target is built through our small
[installation wrapper](cmake/CMakeLists.txt). The wrapper adds the installation
rules missing upstream. It excludes examples and Python integration and keeps
the native C algorithms unchanged. [Provenance](PROVENANCE.md) records the
version, authorship, license and configuration.

A separate CMake consumer uses only installed headers and the shared library.
It rejects include/library paths outside the selected prefix, and `test.sh`
checks the dynamic loader's resolved library path. Application CMake usage is:

```cmake
find_package(Fusion 1.3.3 EXACT CONFIG REQUIRED)
target_link_libraries(my_application PRIVATE Fusion::Fusion)
```

Set `CMAKE_PREFIX_PATH` to the installation and include `<Fusion.h>`.
Follow the pinned upstream API: `FusionBias` handles gyroscope offsets;
`FusionAhrsSettings.sampleRate` sets the fixed update rate. Inputs must use
degrees/second and g with calibrated, consistently aligned sensor axes.

## Synthetic contract

All fixtures use NWU coordinates and 100 Hz samples. Time is simulated by
sample count; these checks do not measure wall-clock scheduling or throughput.
Quaternion references and sensor vectors use independent double-precision
trigonometry. Angular error is sign-invariant and calculated after independent
normalisation. Every AHRS update must produce finite quaternion elements and
norm error below 0.001, accommodating upstream's default fast inverse square
root.

| Case | Input and assertion |
|---|---|
| Static | Three orientations, including two tilted poses, each held for 20 simulated seconds. Converged angular error below 0.25 degrees, linear acceleration below 0.003 g, startup completed. |
| Rotation | Six-axis 90-degree yaw in one second, error below 0.1 degrees throughout; nine-axis full yaw turn in eight seconds, error below 0.2 degrees throughout. |
| Bias | Three-second stationary detection, then 60 seconds of constant synthetic bias. Residual below 0.001 degrees/second; motion does not alter the learned offset. Ten-second corrected attitude error below 0.05 degrees while the raw-input control drifts over 5 degrees. Saved offset restoration is checked. |
| Reset | Restart a rotated filter, require identity and cleared recovery flags, then compare every step with a freshly initialised filter and verify convergence to another tilted orientation. |

## Validation

On 2026-10-07 all four installed-consumer cases passed in a NetBSD 11.0
EmberBSD ARM64 VM with GCC 12.5.0, CMake 4.3.3 and Ninja 1.13.2. The library
was built with one job at reduced priority. The dynamic loader resolved
`libFusion.so.1.3.3` from this profile's installation, with base-system
`libm`, `libgcc_s` and `libc`. The same four cases passed on macOS/ARM64
with AppleClang 21.0.0. These are software runtime checks in a VM and host.

| Native VM measurement | Result |
|---|---:|
| Worst static angular error | 0.014768 degrees |
| Worst six-axis / nine-axis rotation error | 0.001816 / 0.008405 degrees |
| Worst quaternion norm error | 0.000150165 |
| Residual stationary gyroscope bias | 0.00057105 degrees/second |
| Corrected / raw attitude error after 10 seconds | 0.003271 / 8.128408 degrees |

## Boundaries

The bias case exercises a stationary estimate feeding the six-axis AHRS.
It does not claim that a fixed threshold can distinguish every slow physical
rotation from sensor bias. No physical sensor, bus driver, timestamps,
calibration procedure, vibration, temperature change or magnetic interference
has been validated. ENU/NED, rejection/recovery behavior and external heading
are outside these four contracts. Synthetic duration is not a hardware soak.

# OMPL source provenance

[OMPL 2.0.2](https://github.com/ompl/ompl/releases/tag/2.0.2) was released on
2026-08-14 and was the current stable version checked on 2026-10-07.
[sources.tsv](sources.tsv) pins the official release asset `ompl-2.0.2.tar.gz`
by SHA256 `b9155e243e555b04b01f8e4ff7e21a48582edbab9c300a611289655778bcd29d`.
This is the complete release tarball, including upstream's vendored submodules,
not a git tag archive missing those components.

OMPL retains its BSD-3-Clause license and Rice University/contributor authorship.
Bundled VAMP and nanobind sources remain untouched but are not configured or
compiled in this headless C++ profile. Their presence in the archive is not
a claim that accelerated collision checking or Python bindings are supported.

The recipe requires common Eigen 5.0.1 and Boost 1.91.0 installations. Eigen is
provided by the sibling robotics-foundations profile, under its source receipt
and MPL-2.0 license. Boost remains the common image package under the Boost
Software License 1.0. No alternate Eigen or Boost version is installed here.
Serialization and program_options are the upstream-required Boost components;
the installed OMPL library links serialization and system threads.

Optional Triangle, FLANN, Spot, yaml-cpp, documentation, VAMP, demos, upstream
tests and Python discovery are disabled explicitly. No dependency is fetched
by CMake. No upstream patch is currently required or claimed; native validation
is pending and may reveal a portability issue.

The selected C++ library configuration does not invoke Python. Upstream still
installs `ompl_benchmark_statistics.py`; that optional benchmark postprocessor
requires Python when invoked. It is not part of this profile's build or tests.

The shell, CMake and C++ consumers are original AI-assisted EmberBSD work under
the accompanying MIT license. The geometry validator was compiled and executed
on the host. Full OMPL compilation and installed/native tests remain pending;
the host lacks the required Boost 1.91 development installation.

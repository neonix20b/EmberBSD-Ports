# Robotics Foundations Validation Plan

> **For agentic workers:** Use superpowers:executing-plans to execute inline.

**Goal:** Prove useful native workflows on current OpenCV, Eigen and gpsd.
**Architecture:** Pinned source probes, private installation, installed consumers.
**Tech Stack:** C/C++17, shell, CMake/Ninja, upstream SCons/Python.
**Spec:** [design.md](design.md).

## Global Constraints

- OpenCV 5.0.0, Eigen 5.0.1, gpsd 3.27.5; verify SHA256 before extraction.
- No project-owned Python; no shared VM changes; no hardware support claims.
- English public files, private build products, preserved upstream licensing.
- Remove the task's temporary VM and unneeded caches after exporting results.

## Review Focus

- An archive mismatch must stop before extraction (task 1 checksum negative check).
- An existing work directory must never be overwritten (task 1 refusal check).
- Installed consumers must use the pinned versions (task 1 exact CMake/header checks).
- Invalid data must not masquerade as valid sensor output (task 2 malformed input checks).
- Missing daemon or stalled input must fail within a deadline and stop owned children (task 2 negative run).

## Task 1: Vision and numerical probe

Files: `probes/robotics-foundations/{sources.tsv,build.sh,README.md}` and
`tests/{CMakeLists.txt,eigen.cpp,opencv.cpp}`.
Interface: `sh build.sh NEW_ABSOLUTE_WORK [ARCHIVE_DIRECTORY]`; installs all
selected components under `WORK/install`, preserves stage logs under `WORK/logs`.

- [x] Add installed-consumer tests with exact versions, residual tolerances,
  image invariants, features, pose recovery, malformed input and Eigen conversion.
- [x] Add checked downloads and native builds; reject existing work and bad hashes.
- [x] Run on EmberBSD; examine logs and installed dynamic dependencies.

## Task 2: gpsd daemon probe

Files: `tests/gpsd.c`, additions to build/test configuration and README.
Interface: `gpsd-contract ABSOLUTE_GPSD`; local PTY and libgps, finite deadline.

- [x] Implement synthetic NMEA good fix / bad checksum / lost fix / recovery test.
- [x] Verify a missing daemon produces failure; build native gpsd and run upstream
  available checks and the installed-daemon test; examine errors before patching.
- [x] Run the complete installed-consumer suite and preserve versions/hashes/logs.

## Task 3: Evidence and cleanup

Files: public README/profile, related private wiki page and measurement receipt.

- [x] Review changes once with a fresh reviewer; address material findings.
- [x] Export compact install archive and test evidence, stop and delete own VM/caches.
- [x] Update actual scope, check links and diff, commit and push only task files.

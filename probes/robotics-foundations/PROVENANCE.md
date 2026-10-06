# Source and patch provenance

Release metadata checked 2026-10-06:

| Component | Tag | Commit |
|---|---|---|
| OpenCV | 5.0.0 | 40738fb16ceddb5fb3fea747585f7ce6abb0605b |
| Eigen | 5.0.1 | bc3b39870ecb690a623a3f49149a358b95c5781d |
| gpsd | release-3.27.5 | 1d622f5b2c7bf79fc117185be10048e7d4e73c66 |

Archive origins and SHA256 values are in [sources.tsv](sources.tsv).
Upstream references: [OpenCV release](https://github.com/opencv/opencv/releases/tag/5.0.0),
[Eigen release](https://gitlab.com/libeigen/eigen/-/releases/5.0.1),
[gpsd tag](https://gitlab.com/gpsd/gpsd/-/tags/release-3.27.5).

## OpenCV NetBSD AArch64 CPU baseline

`patches/opencv-netbsd-arm64.patch` modifies upstream `modules/core/src/system.cpp`.
The unmodified GCC build initializes neither NEON nor FP16 on NetBSD AArch64
and aborts before `main` because both are required baseline features. Linux's
AArch64 branch already sets these two baseline features unconditionally; it
uses `/proc/self/auxv` only for optional extensions. The 4.x upstream file
checked on 2026-10-06 still lacks a NetBSD branch.

The local patch adds the AArch64 ABI baseline on NetBSD: Advanced SIMD and
half/single-precision conversion. OpenCV's `CPU_FP16` here means conversion,
not the optional FP16 arithmetic extension (`CPU_NEON_FP16`). Dot product,
FP16 arithmetic, BF16 and SVE remain unadvertised. The patch does not disable
the CPU baseline guard and does not change non-NetBSD or 32-bit ARM behavior.

The installed OpenCV contract reproduces the original startup abort. It also
checks the two runtime feature bits and exact half conversion round trips,
then executes image processing and geometric algorithms. The patch is local,
AI-assisted, and has not been submitted to or accepted by upstream.

Eigen and gpsd sources are unmodified. Mounting the built-in ptyfs in a
single-user lab guest is test-environment preparation, not a gpsd patch.

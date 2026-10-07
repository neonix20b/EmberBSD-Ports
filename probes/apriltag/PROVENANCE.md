# AprilTag source provenance

[AprilTag 3.4.5](https://github.com/AprilRobotics/apriltag/releases/tag/v3.4.5)
was the latest official stable release checked on 2026-10-07.
[sources.tsv](sources.tsv) pins the official tag archive and SHA256.
The tag resolves to commit `94be783968e5091bcc9972c72c84fd63efce2935`.
The code retains the upstream BSD-2-Clause license and University of Michigan
copyright. The complete license is copied to
`install/share/ember-apriltag/licenses`.

`patches/ctype-unsigned-char.patch` is a local EmberBSD adaptation authored
with AI assistance. It casts `char` values to `unsigned char` before calling
`islower`, `isupper`, `isspace` and `isdigit`. NetBSD's macro implementation
exposed these arguments through `-Werror=char-subscripts`; signed negative
values are also outside the C ctype API domain. The native unpatched build
failed in `common/getopt.c`; patched installed tests cover ASCII and all high
bytes. This patch has not been submitted or accepted upstream. Its SHA256 is
`ac8adf0fe0d0e7935ef3968c8e484dd9daa52f05899fd91b21c3cb0ef3ed9ffc`.
Upstream copyright and license headers remain unchanged.

The native C shared library is installed using upstream CMake.
Camera/OpenCV examples and the optional Python wrapper are
explicitly disabled: the retained workflow is C image detection and numerical
pose estimation. This configuration has no Python build or runtime dependency.

The shell, CMake and C contract are original EmberBSD work, AI-assisted and
MIT-licensed. The fixture uses upstream `apriltag_to_image` for tag36h11 ID 42;
our inverse image transform supplies independent expected center, scale,
rotation and translation. No downloaded tag bitmap or third-party example
code is copied into the test. Generated images remain in memory.

The native validation VM booted a separately supplied QEMU `-kernel` Image
from EmberBSD revision `b4f718dabd085ed117a24f84d8558e4a43091dc0`.
Its SHA256 is `49395ea85b1c31e8c9eb41dce5bb29c2636ecc1c17785370375a7fb517cc8d2a`;
the matching ELF SHA256 is `fe0fe339059cc1d820c381a8553904e4163a33af8d3cc7fa25348ae75eae3b82`.
The guest's `/netbsd` file hash is inventory only and does not identify the booted kernel.

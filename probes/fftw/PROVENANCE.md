# FFTW provenance

[FFTW 3.3.11](https://www.fftw.org/download.html) is the official stable
release verified on 2026-10-07. [sources.tsv](sources.tsv) pins the official
release archive and its SHA256. Release tarballs contain generated codelets
and configure scripts; no OCaml generator or autoreconf is required.

Both float and double libraries come from this one upstream version.
The profile enables shared libraries and POSIX threads, disables Fortran
wrappers and documentation, and does not request architecture-specific SIMD.
It uses the native compiler and GNU make. It has no Python dependency.
No upstream source patches are applied.

FFTW is GPL-2.0-or-later, copyright Matteo Frigo and Massachusetts Institute
of Technology. The public fftw3.h header has its own BSD-style license,
which does not relicense the library. Original notices remain unchanged;
COPYING is installed under share/ember-fftw/licenses.
The original shell, CMake and C tests here are AI-assisted EmberBSD work
under [MIT](LICENSE). Distributing linked consumers must respect FFTW's
license; this probe does not offer an alternative commercial license.

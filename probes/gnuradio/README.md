# GNU Radio 3.10.12.0 headless source profile

This profile supplies GNU Radio's runtime, blocks, analog, FFT, filter, digital
and channel libraries for C++ signal-processing applications on NetBSD/aarch64.
It installs shared spdlog 1.17.0 with the common external fmt 12.2.0 dependency.
EmberBSD Ports owns the source recipe and installed consumer checks. This is a
source probe, not a pkgsrc package or physical SDR support.

## Shared dependencies

Build and test the sibling [FFTW](../fftw/README.md) and [VOLK](../volk/README.md)
profiles first. Their prefixes supply FFTW 3.3.11 (single precision and threads),
VOLK 3.3.0 and fmt 12.2.0. This profile reuses common image Boost 1.91.0 and GMP
6.3.0 under `/usr/pkg`. It does not install older Boost or duplicate fmt.

The build also needs C/C++ compilers supporting C++17, CMake, Ninja, pkg-config,
tar, patch, SHA256 and upstream's Python/Mako generators. The tested image's
Python is 3.13.14 with Mako 1.3.12 and packaging 26.2. These are existing build
tools; the helper does not install Python packages. Bindings, Companion, Qt,
hardware interfaces, optional post-install actions and upstream examples are
disabled. Optional WAV file blocks are disabled explicitly with
`CMAKE_DISABLE_FIND_PACKAGE_SNDFILE=ON`; this radio/FFT profile does not pull
libsndfile and its audio codecs from the host. C++ applications do not require
a Python runtime.

```sh
export PATH=/usr/pkg/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CC=/usr/bin/cc CXX=/usr/bin/c++
export PYTHON_EXECUTABLE=/usr/pkg/bin/python3.13
export FFTW_PREFIX=/absolute/fftw-work/install
export VOLK_PREFIX=/absolute/volk-work/install
JOBS=1 ./build.sh /absolute/new/gnuradio-work
./test.sh /absolute/new/gnuradio-work
```

For an offline build, supply a cache containing both archives from
[sources.tsv](sources.tsv) as the second build argument. All archive and patch
hashes are verified before extraction or patching. Work must be new. Logs remain
under `WORK/logs` and the installation under `WORK/install`.

Build and test helpers default to `BUILD_AS_KIB=1572864`, a per-process address
space limit of 1.5 GiB enforced with NetBSD `/bin/sh` `ulimit -v`. Keep `JOBS=1`
on the tested 4 GiB VM. Override the limit explicitly for a different host.
Source extraction ignores archive timestamps so host/VM clock differences do
not cause Ninja to regenerate repeatedly.

`CONFIGURE_ONLY=1` builds the small spdlog dependency and configures GNU Radio,
then explicitly stops before GNU Radio compilation. This is useful when sharing
a resource-limited VM; configuration alone does not establish a usable library.
Resume with `JOBS=1 ./finish-build.sh /absolute/gnuradio-work`, which builds,
installs and preserves source/license metadata. Ordinary `build.sh` invokes
the same helper and completes all stages.

The optional `tests/source-guards.sh /absolute/new/guard-work`, with the same
dependency environment, proves a corrupt archive is rejected before extraction
and an existing work directory is preserved. It does not download or build.

## Installed consumer

Set `CMAKE_PREFIX_PATH` to the GNU Radio, VOLK and FFTW prefixes and request
`find_package(Gnuradio 3.10.12.0 EXACT CONFIG REQUIRED COMPONENTS blocks fft
filter analog digital channels)`. Link the exported
`gnuradio::gnuradio-runtime`, `gnuradio::gnuradio-blocks` and other requested
targets. The installed dependency configuration supports modern Boost without a
separate Boost.System binary, using the original NetBSD pkgsrc patches.

Three C++ contract cases check the installed interface:

- A finite scheduler delivers 1025 scaled samples and binary decisions, retaining
  a stream marker's value and offset. It also constructs the channel hierarchy
  and checks the installed filter coefficient interface.
- Prime-length and power-of-two FFTs agree with an independent double-precision
  DFT, and inverse transforms reconstruct the input. Invalid worker counts fail.
- Invalid stream item sizes fail before scheduling. A repeating source processes
  data, stops, waits and restarts twice. Invalid interpolator phases fail.

Every case verifies the runtime release and detected installation prefix.
Tests isolate preferences, FFTW wisdom, state and temporary files beneath the
work directory, preserving HOME. Exit status and CTest timeouts determine
success. Dynamic-link checks require the selected GNU Radio, spdlog, VOLK, fmt
and FFTW prefixes and the base C++ ABI.
The runtime also explicitly declares NetBSD's `librt` dependency for POSIX
shared memory; the test checks its ELF dependency entry.

## Native result

On 2026-10-07, all three installed C++ cases and ELF dependency checks passed
on a NetBSD 11.0 ARM64 VM. The build used base GCC 12.5.0, CMake 4.3.3 and
Ninja 1.13.2. Output libraries are ELF64 AArch64 and use base `libstdc++.so.9`
and `libgcc_s.so.1`. GNU Radio plus spdlog occupies 12,128 KiB installed;
the retained work directory occupied about 94 MiB including sources and logs.

The original runtime left `shm_open` and `shm_unlink` unresolved, so linking
`gnuradio-config-info` failed. The NetBSD-only `librt` patch made that same
link succeed. The installed consumer checks the runtime's `librt.so.1`
dependency and ran with the upstream `vmcircbuf_mmap_shm_open_factory`.
Initial automatic buffer selection reported `shmat: Too many open files`
while testing SysV shared memory, then successfully selected the POSIX backend.
No global IPC limit or buffer-selection override was applied.

The source-guard tests rejected a corrupt archive before extraction and
preserved an existing work directory. Focused configuration also demonstrated
the original Boost.System dependency failure and success with the attributed
pkgsrc patch. The complex channel noise getter exposes amplitude divided by
sqrt(2); the contract follows that upstream convention.

Explicit CPU affinity remains unimplemented in GNU Radio's upstream NetBSD/BSD
thread branch; this profile does not call it or replace it with a silent stub.
Real-time scheduling, physical radios, GUI, Python bindings, hardware clocks and
long-running stream reliability are outside the tested contract. See
[provenance](PROVENANCE.md) for source licenses and patch origin.

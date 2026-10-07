# liquid-dsp source probe

Filter sampled signals, change sample rates, inspect spectra and recover
QPSK symbols with liquid-dsp 1.8.3 on EmberBSD. This Ports-owned probe
installs the shared C library and uses the common FFTW 3.3.11 float library.
The independent installed consumer needs no radio, audio device or Python.
This is a source profile, not an installable package or SDR hardware stack.

## Build and test

First build and test [the common FFTW profile](../fftw/README.md).
Use a native C/C++ compiler, CMake 3.18 or newer, Ninja, tar, patch, nm and
`sha256` or `shasum`. curl is only required without a source cache.

```sh
FFTW_PREFIX=/var/tmp/ember-fftw/install JOBS=1 \
  sh probes/liquid-dsp/build.sh /var/tmp/ember-liquid
sh probes/liquid-dsp/test.sh /var/tmp/ember-liquid
FFTW_PREFIX=/var/tmp/ember-fftw/install \
  sh probes/liquid-dsp/tests/build-guards.sh
```

The work path must be absolute and absent. An optional second build argument
names an absolute archive cache containing [sources.tsv](sources.tsv).
Source SHA256 is verified before extraction. `FFTW_PREFIX` is required:
missing common-profile metadata, a wrong version or an absent shared library
stops the build. The recipe passes the exact FFTW include and shared-library
paths to CMake. There is no system FFTW or built-in FFT fallback in this profile.

`CC`, `CXX` and `JOBS` select compilers and build parallelism; one job is the
default. All source, build, install and log files stay under the work directory.
Keep the FFTW installation available for the lifetime of liquid-dsp: its
shared library records the chosen dependency directory in its runtime path.
The dependency prefix is also recorded at
`install/share/ember-liquid-dsp/fftw-prefix.txt`.

Optional examples, upstream autotests, benchmarks, sandbox, documentation,
SIMD discovery and embedded timestamps are disabled. The portable CPU profile
has no Python dependency. No system packages or session settings are changed.

## FFTW integration regression

Upstream 1.8.3 CMake can report FFTW as found while its configured internal
API still selects the bundled FFT. Its imported target also uses the library
file as an include path; object targets lack that dependency, and final
linkage uses a bare library name. The small
[CMake patch](patches/cmake-fftw-selection.patch) repairs all these parts of
the same dependency-selection path.

The build first configures the unpatched source. A compiled regression
requires the generated FFTW selection macro and must fail with
`FFTW_BACKEND_REQUIRED`. After patching, the same regression compiles and
executes an impulse transform through the real selected FFTW library.
The installed libliquid must import `fftwf_plan_dft_1d`, `fftwf_execute` and
`fftwf_destroy_plan`. The spectrum application exercises that backend.
Runtime linkage must resolve libliquid and libfftw3f in their selected
installation prefixes. An independent installed CMake target supplies the
consumer; it does not link source build targets. Discovery caches are cleared
before selecting the requested prefix.

## Signal contracts

The [installed consumer](tests/contract.c) has four timed CTest cases with
explicit runtime checks, including in Release builds:

- **Filter:** a 129-tap Kaiser low-pass filter with cutoff 0.12 cycles/sample
  processes tones at 0.03 and 0.31. After settling, normalized passband gain
  must be within 0.5% of unity and stopband gain below −60 dB.
- **Resampler:** a tone at 0.06 cycles/input-sample is resampled at rate 3:2.
  Output count must match 3072 for 2048 inputs within one sample, output
  frequency must be within `1e-5` of 0.04 cycles/output-sample, and amplitude
  within 1% of unity. Frequency comes from consecutive-sample phase changes.
- **QPSK:** 4096 deterministic symbols exercise all four unit-energy points.
  Bounded deterministic noise of at most 0.15 on each axis must leave zero
  symbol errors. Deliberately inverting the received constellation must
  change every symbol, providing a negative control.
- **Spectrum:** the FFTW-backed periodogram processes a tone at 0.125
  cycles/sample. Its 256-bin shifted spectrum must peak at bin 160 with
  more than 60 dB rejection at the opposite frequency. Every PSD bin must
  be finite.

Guards reject existing work directories, invalid jobs, relative paths,
corrupt archives and a missing or absent common FFTW profile.

## Validation and limits

On 2026-10-07 the patched native source build, baseline/patched regression,
build guards and all four installed cases passed in an EmberBSD AArch64 VM
with NetBSD 11.0 userland, EMBER64 kernel revision `b4f718d`, base GCC 12.5,
CMake 4.3.3 and Ninja 1.13.2. Filter gain was 1.00002101 in-band and
−107.36 dB out-of-band. Resampling produced 3072 samples, frequency
0.04000011 and gain 0.99995383. QPSK had zero recovery errors and 4096
inverted-symbol errors. The periodogram peak was bin 160 with 60.99 dB
rejection at the checked opposite frequency.

The consumer loaded installed `libliquid.so.1`, which loaded the common
`libfftw3f.so.10`. FFTW's float and double installed contracts passed too.
This establishes synthetic numerical workflows and native shared-library
integration. Physical radio/audio I/O, synchronization over a real channel,
SIMD throughput, real-time operation and sustained device runs remain
unverified. The full liquid-dsp upstream test suite was not run.

[Provenance and licensing](PROVENANCE.md) records the upstream MIT code,
local patch and GPL-2.0-or-later FFTW dependency.

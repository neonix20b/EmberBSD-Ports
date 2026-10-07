# Signal processing and IMU estimation

These source profiles give EmberBSD applications native C/C++ interfaces for
sampled signals, spectra, vector processing and orientation estimation.
They form a common basis for software radio and robotics applications.
Ports owns the recipes, portability patches and installed-consumer checks;
the original projects own their algorithms and retain their licenses.

| Profile | Version | Verified application workflow |
|---|---|---|
| [FFTW](../fftw/README.md) | 3.3.11 | Float/double spectra, real/complex inverse transforms, prime-length inputs and pthread plans |
| [liquid-dsp](../liquid-dsp/README.md) | 1.8.3 | Filter tones, resample a stream, recover QPSK symbols and measure a spectrum through the common FFTW |
| [VOLK](../volk/README.md) | 3.3.0 | Dot products, multiplication and complex magnitude through generic and ARMv8 NEON kernels |
| [Fusion](../fusion/README.md) | 1.3.3 | Estimate orientation, compensate stationary gyro bias and restart the estimator on synthetic IMU data |
| [GNU Radio](../gnuradio/README.md) | 3.10.12.0 | Process tagged streams, compute FFTs, restart a flowgraph and recover a packet through a software radio channel |

## Build order and dependencies

Follow each profile's prerequisites and source manifest. All builds require
a new absolute work directory, verify source hashes before extraction and
preserve nonzero failures. They install into that directory's `install`
prefix and leave the system package set unchanged.

Build FFTW before liquid-dsp, passing its installation explicitly:

```sh
JOBS=1 sh probes/fftw/build.sh /var/tmp/ember-fftw
sh probes/fftw/test.sh /var/tmp/ember-fftw
FFTW_PREFIX=/var/tmp/ember-fftw/install JOBS=1 \
  sh probes/liquid-dsp/build.sh /var/tmp/ember-liquid
sh probes/liquid-dsp/test.sh /var/tmp/ember-liquid
```

Float and double FFTW are two precision interfaces from one upstream release.
liquid-dsp must load that common float library; its profile rejects a missing
dependency and checks actual FFTW symbol imports. Keep this FFTW installation
available to downstream consumers, including the GNU Radio profile.

VOLK and Fusion can be built independently. VOLK's current profile is scoped to
native NetBSD/aarch64 and installs the common fmt 12.2.0 alongside its library.
Its upstream generator uses the image's Python and Mako; the installed C/C++
libraries and consumers do not require Python at runtime. Fusion, FFTW and
liquid-dsp have no Python requirement in these configurations.

Build GNU Radio after FFTW and VOLK, using their prefixes as documented in
its profile. The selected C++ runtime, block, analog, FFT, filter, digital
and channel libraries support the [BPSK channel example](https://github.com/neonix20b/EmberBSD-Examples/tree/main/robotics/gnuradio-channel).
Its upstream build uses Python/Mako; the installed C++ flowgraph does not.

Separate work prefixes isolate source validation. They are not permanent
per-application dependency versions. Consumers must use the same selected
FFTW, fmt and C++ runtime rather than creating older private copies.
The component provenance pages retain licenses and distinguish pkgsrc patches
from local EmberBSD adaptations.

## Native validation

On 2026-10-07 the four DSP/IMU foundation profiles passed 19 installed CTest cases
in an EmberBSD AArch64 VM: NetBSD 11.0 userland, EMBER64 kernel, four virtual
CPUs, approximately 4 GiB RAM and base GCC/G++ 12.5.0. Builds used one job
each. This is the tested environment, not a requirement to keep this compiler.

FFTW passed two precision suites and liquid-dsp four signal workflows.
Fusion passed four IMU cases. VOLK passed nine cases, including 1,144
kernel/length/alignment combinations, C/C++ NaN/Infinity checks and an
installed profiler dry run. No throughput result is inferred from the VM.
Source guards, installed library resolution and relevant baseline/patched
regressions are documented by each profile.

The liquid-dsp patch repairs upstream CMake's FFTW selection and propagation.
VOLK uses existing pkgsrc fixes for current fmt headers and C++ math names,
with original patch identifiers retained. Fusion receives installation and
CMake export rules around its unchanged upstream C target.

GNU Radio passed three additional installed contracts and the standalone
example passed two cases on the same VM. The example recovered 2,048 bits
without error; removing carrier correction produced BER 0.516113. It assumes
a known frequency offset and sampling phase, not general radio acquisition.
The NetBSD adaptation explicitly links the runtime's POSIX shared-memory
functions from librt. Physical SDR, affinity and prolonged streaming are unverified.

These are source profiles, not a released pkgsrc package set. Synthetic
signals and IMU inputs establish the stated software behavior. Physical
radios, audio devices, IMUs, calibration under vibration, real-time deadlines,
other architectures and sustained hardware operation remain unverified.

See [robotics foundations](../robotics-foundations/README.md) for vision and
geometry, [developer tools](../robotics-tools/README.md) for recording and
control logic, and [media](../media/README.md) for file-based video processing.

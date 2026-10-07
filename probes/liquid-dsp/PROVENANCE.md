# liquid-dsp provenance

[liquid-dsp 1.8.3](https://github.com/jgaeddert/liquid-dsp/releases/tag/v1.8.3)
was the latest official stable release checked on 2026-10-07, published
2026-09-26. [sources.tsv](sources.tsv) pins the original tag archive and SHA256.
The upstream MIT license and Joseph Gaeddert's copyright are preserved;
LICENSE is copied into install/share/ember-liquid-dsp/licenses.

The shared library uses the explicit common [FFTW 3.3.11](../fftw/README.md)
float library. FFTW remains GPL-2.0-or-later; the MIT license of liquid-dsp
does not remove licensing obligations for the combined distribution.
The build uses CMake, Ninja and native C/C++ compilers. Optional examples,
autotests, benchmarks, documentation and SIMD discovery are disabled.
This portable CPU profile has no Python dependency.

The local patch [cmake-fftw-selection.patch](patches/cmake-fftw-selection.patch)
repairs upstream CMake dependency propagation. The original configuration
commented out the generated FFTW selection macro, omitted include paths
from object targets, linked a bare library name, and assigned a library file
as an imported include directory. The patch enables the generated macro,
uses the found imported target for objects and final linkage, and corrects
its include directory. Public DSP APIs and FFT algorithms are unchanged.
The upstream master configuration still had the commented-out macro when
checked on 2026-10-07. The patch is AI-assisted EmberBSD work, not submitted
or accepted upstream. Its code follows the upstream MIT license.

The build configures the original source and confirms that a compiled
backend-selection regression fails with FFTW_BACKEND_REQUIRED. After the
patch the same source compiles and executes an eight-sample impulse FFT.
The installed library must import fftwf_plan_dft_1d, fftwf_execute and
fftwf_destroy_plan. The installed spectral consumer and runtime linkage
checks further establish actual use of the selected shared FFTW library.

Original shell, CMake and consumer tests are AI-assisted EmberBSD work
under [MIT](LICENSE). Test signals are generated analytically; no radio
capture, third-party fixture or trained data is used.

Tag v1.8.3 resolves to commit
`10041f70cebbe3b97887e75bb41e48b73dda1b23`; its annotated tag object is
`6470d5cdba3d2713e452a96109fe07fa970cad90`.
The local patch SHA256 is
`319226bf9468366108a1762cc74c321522bda5170bd77c74bd62e5294f3bd151`.

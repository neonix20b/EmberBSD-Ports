# Full Compass UMD cross-build and no-device API probe

This probe compiles the complete official hardware `standard_api` at pinned
Compass revision `2868d533694740de6891f9998812ceb62a899dee`, paired UMD/KMD
6.1.1. `aipu_all` builds all 27 translation units, including v1/v2, v3 and
v3.2, into `libaipudrv.so.6.1.1` and `libaipudrv.a`. This is a source probe,
not an installable or usable native NPU backend. Nothing is installed.

The Mac cross build uses the common GCC 16.2 and NetBSD/AArch64 sysroot.
It has passed full shared/static linking with `-z defs`, real `libexecinfo`
and the single GCC16 C++ runtime. On 2026-10-08 the complete library also passed
85 public no-device API checks over four cycles on an Orange Pi Zero 3W
(A733, 4 GiB), running EmberBSD's NetBSD 11/AArch64 kernel `dfe456bf1fb`.
Immediate symbol binding, exact live library providers and descriptor counts
passed. Expected upstream open-failure backtraces were printed; the runner
and consumer exited zero. No device, model or kernel transport was exercised.

Accepted bundle SHA256:
`e490729153b0408a4ea53328b53f37a75deb39cbb9f1ba07dc999055edfa4b24`.
Full DSO SHA256:
`944c28db411ad9e8ae0f1edfbe514406d7a78dece2c96899c8f8cc317077ec01`.

## Reproduce

Download the original archive named in [sources.tsv](sources.tsv), then run:

```sh
ruby probes/compass-umd/build-cross.rb /absolute/original.tar.gz \
  /absolute/new-work /absolute/cross-tools /absolute/sysroot \
  /absolute/gnu-make
```

`CROSS_TOOLS/bin` must provide `aarch64--netbsd-{gcc,g++,ar,readelf}`.
The recipe requires GCC 16.2 and the common sysroot's `/usr/pkg/gcc16` headers
and libraries. It verifies the archive before extraction, applies `0001`–`0003`
without fuzz or offsets, runs the UAPI regression, and builds with two jobs.
It stops before large stages if free space is below 2 GiB. Expected work
usage is below 20 MiB; a completed work tree must remain below 150 MiB.

The original Linux and Android choices remain upstream defaults.
`BUILD_TARGET_OS=NetBSD` explicitly selects the adaptation. `SIMULATION`
is absent, rather than defined as zero. No simulator, Python API, fake
device, fake graph or model is linked. The original `-Wall -Werror -O2`
policy remains. The recipe records tool hashes, all compiler dependency
headers, actual linker inputs, object/archive membership, ELF dependencies,
SONAME and runtime paths. No host headers or DSOs are accepted.

The completed `bundle/` contains the actual full library, archive, consumer,
source receipts and runner. Move this private bundle to the intended target
using a separately verified archive hash. It has no installation command:

```sh
sh /absolute/bundle/run-no-device.sh /absolute/bundle /absolute/new-logs
```

The runner requires NetBSD/AArch64, verifies the entire bundle and both
installed GCC16 runtime hashes, rejects loader overrides, and uses a clean
environment with a 60-second timeout and five-second kill grace. Base OS
libraries are restricted to normal system paths; their hashes are recorded
as build inputs, not required to equal a different target OS image.

The real consumer requires `lstat("/dev/aipu") == -1` with `ENOENT` before
loading, and before each context initialization. A device node or dangling
symlink rejects the test. It loads the exact canonical private DSO with
`RTLD_NOW`, checks each public symbol's `dladdr` provider, and checks the live
loader inventory before releasing its handle. There must be one UMD and one
canonical GCC16 runtime. Four cycles check real open-failure propagation,
cleared context output, null/unknown-context errors, the real error message,
and unchanged descriptor counts. No file is created outside the private logs.
`dlclose` succeeds, but C++ loader retention can keep the DSO mapped; this is
not a claim that all process globals were unloaded or that no heap leaks exist.

## Causal checks

The normal recipe compiles unchanged original UAPI text against the pinned
Linux generic encoders, then the adapted header both before and after native
`sys/ioctl.h`. All builds assert 32 literal command values, 17 structure
size/alignment pairs, 16 field offsets and native macro preservation.
Three private mutations (wrong direction, native `_IOR`, shortened ASIDs)
must fail static assertions. The entire structure/enum source interval must
remain byte-for-byte identical. These are ABI compile checks, not ioctl calls.

After the full build, run the small additional regressions:

```sh
ruby probes/compass-umd/tests/make-order.rb /absolute/new-work/original \
  /absolute/new-work/source /absolute/gnu-make /absolute/new-order-work
ruby probes/compass-umd/tests/link-deps.rb /absolute/new-work /absolute/new-link-work
ruby probes/compass-umd/tests/bundle-guards.rb /absolute/new-work/bundle \
  /absolute/sysroot /absolute/new-guard-work
```

The actual Makefile regression deliberately delays directory creation and
uses compiler/archive stubs to expose the original parallel dependency race.
The fixed graph produces all 27 stub objects. Separately, the real 27 full
objects are relinked: Linux `-ldl` and missing `libexecinfo` must fail, while
the accepted full link passes. The actual verifier accepts the intact bundle
and rejects altered consumer/DSO/runtime, a missing source, an added DSO and
a substituted symlink. These controls do not execute target code on the host.

## Native transport remains separate

NetBSD `_IO*` cannot silently replace Linux command encodings. This adapter
preserves the pinned Linux wire values and four-ASID layout only. Native
NetBSD ioctl dispatch copies encoded argument sizes itself; the Linux KMD
instead uses user pointers and variable-length partition/status arrays.
Equal command numbers therefore do not establish a usable native transport.
Mapping, DMA/PRIME, coherency, scheduling, interrupts, reset and repeated
inference require an OS-owned matched KMD/UAPI and real hardware acceptance.
The A733 no-device API run establishes loader/API portability on that CPU,
not CIX hardware support or accelerated model execution.

See [PROVENANCE.md](PROVENANCE.md) for upstream identities, licenses and the
explicit AI-assisted local adaptation. The existing lifetime/core-count
regressions are independent and remain unchanged.

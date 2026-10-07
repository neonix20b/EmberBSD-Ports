# GTSAM source profile provenance

Source selection was checked on 2026-10-07 against the official
[GTSAM 4.3.0 release](https://github.com/borglab/gtsam/releases/tag/4.3.0)
and [installation guide](https://gtsam.org/get_started/).
The stable release was published on 2026-09-18 UTC, described as September 19
on the project website. This is not the earlier 4.3 alpha release.

The annotated tag object `97b7a5e3b8edce204320397f00b502f57952fb38` resolves to
commit `71a25ca36c084cbad1f872e812d6d97fbadfdb05`.
[sources.tsv](sources.tsv) pins that commit's upstream archive and its SHA256.
The archive is 45,746,023 bytes and the extracted source tree occupies about
141 MiB on the source preparation host. A completed build footprint has not
been measured.

GTSAM is BSD-3-Clause, copyright Georgia Tech Research Corporation and the
individual contributors. The build retains `LICENSE`, `LICENSE.BSD` and
source notices. The recipe does not patch GTSAM source.

## Dependencies and original licenses

| Component | Selection and provenance |
|---|---|
| Eigen 5.0.1 | Existing common external installation; MPL-2.0 and upstream per-file notices. GTSAM's bundled Eigen 3.4.0 is unused and not installed |
| CCOLAMD 2.9.6 | Upstream internal vendor copy in `gtsam/3rdparty/CCOLAMD`; Tim Davis, BSD-3-Clause, `Doc/License.txt` |
| SuiteSparse_config | Internal companion to CCOLAMD; its `README.txt` says no licensing restrictions apply |
| Spectra 1.1.0 | Upstream internal headers in `gtsam/3rdparty/Spectra`; Yixuan Qiu, MPL-2.0; version from `Util/Version.h` and notices retained |
| Cephes | GTSAM's upstream vendor copy in `gtsam/3rdparty/cephes`; MIT top-level license, Stephen L. Moshier attribution, and BSL-1.0 notices for John Maddock-derived code with SciPy changes |

These internal copies are supplied by the selected current GTSAM release.
They do not create parallel public provider packages. GTSAM's CCOLAMD wrapper
uses its vendor namespace and hidden implementation symbols. Its optional
system-provider paths can replace CCOLAMD/Spectra during common dependency
integration. The profile does not install or link the bundled METIS.

The builder copies original license files and representative Spectra/Cephes
source notices into its private installation; the complete source archive
retains every individual file notice. Optional Python and MATLAB wrappers
are disabled. No new project-owned helper is written in Python.

The recipe and installed consumer checks were written for EmberBSD with AI
assistance and are MIT licensed; see [LICENSE](LICENSE). No upstream acceptance
is claimed. Native configuration succeeded on 2026-10-07; compilation was
interrupted by the user's scope closure with exit status 130. No installed
consumer execution result is available; see [status](README.md).

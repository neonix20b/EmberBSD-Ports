# Ceres probe provenance

Source selection was checked against official upstream tags on 2026-10-07.

| Component | Upstream source | License |
|---|---|---|
| Ceres Solver 2.2.0 | [tag](https://github.com/ceres-solver/ceres-solver/tree/2.2.0), commit `85331393dc0dff09f6fb9903ab0c4bfa3e134b01` | BSD-3-Clause; upstream `LICENSE` and source notices |
| Eigen 5.0.1 | [release](https://gitlab.com/libeigen/eigen/-/releases/5.0.1) | MPL-2.0, with additional licenses identified by upstream `COPYING*` and individual files |

[sources.tsv](sources.tsv) pins archive URLs and SHA256 checksums. The builder
checks every archive before extracting any and preserves upstream license files
in the private installation. Archives and build output are not repository files.

Ceres 2.2.0 is the latest stable tagged release, although newer development
documentation describes Abseil. This release supports its own `MINIGLOG` profile
and does not require Abseil. The probe enables that upstream implementation;
it does not add a logging stub. Abseil's current release was
[20260817.0](https://github.com/abseil/abseil-cpp/releases/tag/20260817.0) when
checked, but no Abseil version is installed by this probe. The same Eigen 5.0.1
is selected by the other robotics probes; no obsolete Eigen version is added.

## Local adaptation

`patches/ceres-eigen5.patch` changes the CMake dependency request from Eigen 3.3
to the common Eigen 5.0.1 exactly. Eigen 5's package-version policy rejects the
original 3.3 request before compilation. The patch does not override Eigen's
version metadata or modify its source. The installed consumer independently
requires 5.0.1 and checks its header version, then fits a known nonlinear model.
The failed unpatched configure and patched build/runtime checks establish the
regression boundary. This is a local EmberBSD profile patch, not an upstream
accepted change.

The probe recipes, patch and consumer tests were written for EmberBSD with AI
assistance and are MIT licensed; see [LICENSE](LICENSE). Upstream authorship
and licenses remain unchanged.

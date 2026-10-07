# Fusion source provenance

[Fusion v1.3.3](https://github.com/xioTechnologies/Fusion/tree/v1.3.3)
was the latest upstream version tag checked on 2026-10-07 through the
[official tag list](https://api.github.com/repos/xioTechnologies/Fusion/tags).
Upstream does not publish GitHub Releases. The tag resolves to
[`9325424011892abacc0ce42b8bb1a8ae20264b9b`](https://github.com/xioTechnologies/Fusion/commit/9325424011892abacc0ce42b8bb1a8ae20264b9b),
whose commit date is 2026-08-30. [sources.tsv](sources.tsv) pins the tag archive
and SHA256 `84fc2a6e04f4e2fe4388f506040b3f63359293902211be562bb767b93962161d`.

Fusion is MIT-licensed, copyright 2021 x-io Technologies. Source files retain
Seb Madgwick's author notices. The complete upstream license is installed in
`share/ember-fusion/licenses/Fusion-MIT`. Sources are neither vendored here nor
patched. This is the upstream native C implementation, not the Python wrapper.
The retained library and our consumer require no Python.

Upstream's CMake library target lacks install rules and package exports.
Our CMake wrapper includes that native target and adds headers, a shared
library, and the `Fusion::Fusion` installed export. The exact 1.3.3 SONAME and
package version describe this profile, without promising ABI compatibility
with other upstream versions. No algorithm changes or alternate square-root
configuration are applied. Upstream's default fast inverse square root remains.

The build/test scripts, installation wrapper and synthetic C contracts are
original EmberBSD work, authored with AI assistance and MIT-licensed under
[LICENSE](LICENSE). No changes have been submitted to or accepted by upstream.
Fixtures use independently calculated analytic rotations and ideal sensor
vectors; they do not copy an upstream example or a hardware dataset.

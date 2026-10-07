# iso14229 source provenance

Checked 2026-10-07: the official
[latest release](https://github.com/driftregion/iso14229/releases/latest) is
**0.11.0**, published 2026-09-28. The tag resolves to
`8a7eb23d6ab9d52f66ce36b07ba456613709c78e`.

Use the official **release asset** `iso14229.zip`, not the tag source archive.
The exact asset URL and SHA256 are in [sources.tsv](sources.tsv), and GitHub's
release API advertises the same SHA256:
`527b85114754dda84c8d0b81739cf808a5fb4a2b50107187742b93838d936e8b`.
The ZIP's VERSION and generated `UDS_LIB_VERSION` both say `0.11.0`.
Its `iso14229.c` and `.h` SHA256 values are respectively
`a22f1c6afe87247a3513f816f37eacb1976a554d7c3dfd33a65911a705f669c5` and
`30eec21f69f42de2ce02d2f3031c300ca8494b94999bee00c1feedd2adece0ad`.

In contrast, the tag archive at
`https://codeload.github.com/driftregion/iso14229/tar.gz/refs/tags/0.11.0`
has SHA256 `e78c76e864d7fa8ee317a8d332ce38d4dd3cbd874b3c3635bc790fcca4675a70`.
Its checked-in generated header identifies itself as `0.10.2` and differs
from the release API/configuration. It is not an equivalent build input.
The probe verifies the ZIP before extraction and checks VERSION, header and
runtime-consumer version. No source-generation step or Python is needed.

iso14229 is MIT licensed, copyright Nick James Kirkby & Co-Operators.
The amalgamation includes `isotp-c` notices and MIT licenses; these are retained
in the installed header. The original LICENSE and AUTHORS.txt are installed.
No upstream source is patched. Compilation explicitly uses
`UDS_AUTOSELECT_TP=0` and `UDS_TP_ISOTP_C`. The release's automatic Unix transport
selects Linux CAN_ISOTP sockets, which must not be inferred from NetBSD raw CAN.
The consumer supplies a bounded in-memory CAN-frame adapter and a monotonic
microsecond clock. Real ISO-TP segmentation, flow control and reassembly remain
in upstream's included `isotp-c` implementation.

Upstream marks its major-zero API unstable. Its
[contribution policy](https://github.com/driftregion/iso14229/blob/0.11.0/CONTRIBUTING.md)
forbids AI-authored upstream communication and contributions. This is an
explicitly authorized local downstream probe; no issue, message, patch or
submission was sent upstream. The helpers and consumer are MIT-licensed
EmberBSD code written with AI assistance. They do not imply upstream acceptance.

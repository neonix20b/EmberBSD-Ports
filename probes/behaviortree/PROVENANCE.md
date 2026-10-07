# BehaviorTree.CPP probe provenance

The official [4.9.0 release](https://github.com/BehaviorTree/BehaviorTree.CPP/releases/tag/4.9.0)
was the latest stable release when checked on 2026-10-07. Its tag identifies
commit `3ff6a32ba0497a08519c77a1436e3b81eff1bcd6`.
[sources.tsv](sources.tsv) records the original archive URL, SHA256, and the
supplemental upstream license texts. All inputs are verified before extraction.

BehaviorTree.CPP is MIT licensed. Its original authors include Michele
Colledanchise and Davide Faconti; individual notices remain unchanged.
The selected release bundles tinyxml2 (zlib license), minicoro and minitrace
(MIT), a FlatBuffers 24.3.25 scalar header (Apache-2.0), and public contrib
headers including nlohmann JSON 3.11.3 and magic_enum 0.9.5 (MIT), `any` and
`expected` (Boost Software License 1.0). These are the upstream release's
embedded implementations; the probe adds no parallel installed dependency
libraries. Their source notices and installed public header notices are retained.
Missing full FlatBuffers, Boost and JSON license texts are fetched from their
official tagged repositories, verified and saved with the installed licenses.
The Boost input is a license text, not another Boost build.

The profile disables optional SQLite and ZeroMQ/Groot connections. It does not
install a second SQLite version. A future SQLite-enabled profile must use the
common SQLite 3.53.4 and test its logger. The native binary transition logger
remains included and is exercised without SQLite or a Groot connection.

No upstream source patch is applied. The independent shell/C++ probe and tests
were prepared for EmberBSD with AI assistance under [MIT](LICENSE). No upstream
acceptance is claimed, and no Python helper or build step is introduced.

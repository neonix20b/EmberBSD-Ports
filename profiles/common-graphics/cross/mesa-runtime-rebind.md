# Rebind accepted Mesa tests to the common LLVM package revision

`rebind-mesa-runtime.rb` updates an existing accepted Mesa bundle after the
normal sysroot installation of `llvm-23.1.2nb1`. It preserves the accepted
Mesa payload and test binaries. It does not rebuild Mesa, install packages,
run target code, or establish ABI or rendering compatibility by itself.
EmberBSD owns this helper and its fixture regression.

The only supported transition is the accepted `llvm-23.1.2` DSO with SHA256
`42231ed6dbaf213a3a391dff50eb51986b0c8fbb8cff8821c42fa07fbc84b1e6`
to the package `llvm-23.1.2nb1.tgz`, SHA256
`e677db8bb4a579fc697651025ad3cbdcb27345f56a062f64cac88ac3d259397c`.
Its DSO SHA256 is
`59486085a768044e0f1940a067f24be4149c420078ae496972bbea303b7b2eb7`.
These are explicit revision gates, not overrides or a general version policy.
A later package revision needs a reviewed policy and renewed runtime acceptance.

```sh
ruby rebind-mesa-runtime.rb /absolute/accepted-bundle \
    /absolute/llvm-23.1.2nb1.tgz /absolute/sysroot \
    /absolute/cross-tools/bin/aarch64--netbsd-readelf /absolute/new-work
```

`NEW_WORK` must be absent, outside the inputs, with an existing canonical
parent directory. Keep all inputs and the installed sysroot unchanged during
verification. No archive payload is extracted and no LLVM tools are copied.
The helper streams every package file, compares exact installed symlinks,
reconciles the payload with `+CONTENTS`, and checks the installed package
registration under `/usr/pkg/pkgdb` or `/var/db/pkg` (exactly one).
Unsupported archive entries, path overrides, escaping links and symlink
parent directories fail. The accepted bundle must have a complete artifact
inventory and the canonical unmodified verifier.

Old bundle artifacts are checked independently of the updated sysroot; the
old LLVM runtime hash is expected to differ. Only existing runtime-manifest
paths owned by the verified new package can change. Every other runtime
provider and installed Mesa file/link must still match. The original runtime
and artifact manifests are retained in `bundle/runtime-rebind/`. All other
bundle inputs, including whichever test executables it contains, are copied
unchanged. A renderer-only bundle does not gain the 37 upstream tests.

The LLVM SONAME, RPATH and eleven direct `DT_NEEDED` names must match the
accepted LLVM23 inspection. Recursive dependencies must resolve within the
sysroot. Package providers must already belong to the accepted runtime closure
and match their recorded hashes. Base OS providers retain OS ownership; their
resolved paths, hashes and dependency inspection are recorded separately.
This is static dependency verification, not a target loader or execution test.

Only after the normal `--verify-sysroot` verifier passes does `NEW_WORK/bundle`
appear. A failed final check leaves `candidate`, never a published bundle.
`llvm-payload.json`, `llvm.CONTENTS` and `dependency-closure.json` remain outside
the bundle as private sysroot receipts, referenced by SHA256 in its receipt.
The target runtime manifest is not enlarged to require the complete LLVM tools
package in a small VM root. The helper does not create a transfer archive.

Run the host regression with tiny labelled archives and an ELF-inspector fixture:

```sh
ruby ../tests/mesa-runtime-rebind.rb --mutations
```

It executes the production helper bodies, checks immutable input preservation,
full payload and registration checks, version gates, dependency boundaries,
path/link guards, and final-verifier failure. Guard-removal mutants must make
specific invalid inputs succeed before the regression rejects the mutant.
The actual package/sysroot check is a separate validation from these fixtures.
Use the [Mesa acceptance instructions](mesa-package.md#run-on-netbsdaarch64)
for a bundle containing the complete upstream suite. For a renderer-only
metadata bundle, verify its artifacts and installed providers first, then
run only the retained renderer; do not call the full-suite mode:

```sh
sh "$BUNDLE/run-mesa-package-tests.sh" --verify-only "$BUNDLE"
sh "$BUNDLE/run-mesa-package-tests.sh" --verify-sysroot "$BUNDLE" /
env -i PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/pkg/bin \
    MESA_SHADER_CACHE_DISABLE=true /usr/bin/timeout -k 5 60 \
    "$BUNDLE/bin/mesa-render" surfaceless llvmpipe
```

On 2026-10-08, normal package updates installed this LLVM revision into the
cross sysroot and physical Orange Pi Zero 3W (A733). Full verification covered
2,789 LLVM files/links and 16 dependency providers. Four target Mesa shader,
triangle-pixel and EGL/JIT lifecycles passed. A newly prepared libepoxy bundle
also passed four rendering lifecycles, live-provider checks and four pure
upstream tests against the updated provider. The unchanged 37-test Mesa suite
was not repeated. This establishes CPU rendering and dispatch after this
revision update, not a Wayland session or GPU acceleration.

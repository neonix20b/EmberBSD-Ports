# LiteRT CPU acceptance consumers

These project-owned MIT-licensed tests consume the public LiteRT 2.2.0 C API
and C++20 wrappers through shared `libLiteRt`. No inference implementation is
copied into the tests. The C++ consumer selects `LITERT_NO_ABSL` and needs the
local `litert-no-absl-options.patch`; its compilation is the regression for the
public runtime-options header's unconditional Abseil dependency.

`runtime-add.json` describes one `ADD` operator: `z = x + y`, with two dense
`float32[1,4]` inputs and one output. Its `serving_default` signature names the
inputs `x`, `y` and the output `z`. The pinned host `flatc` compiles it using
LiteRT's `tflite/converter/schema/schema.fbs`. The generated binary stays in the
build directory, and no TensorFlow or Python model exporter is needed.

`runtime-vectors.h` supplies three independent exact arithmetic oracles:

| Case | x | y | Expected z |
|---|---|---|---|
| 1 | 1, 2, -3, 0.25 | 10, -2, 0.5, 0.75 | 11, 0, -2.5, 1 |
| 2 | -8, 0, 1024, -0.5 | 3, 7, -1024, -0.25 | -5, 7, 0, -0.75 |
| 3 | 0.5, 16, 2, -4 | 0.25, -8, -3, 4 | 0.75, 8, -1, 0 |

All values are exactly representable in float32. Each consumer reuses one
compiled CPU model and its buffers across all three cases. Changed inputs
detect stale output reuse. The C consumer also checks tensor element types,
layouts, host-buffer support and packed sizes. It rejects missing/malformed
models, invalid signatures, missing input buffers, and undersized, misaligned
or dynamic-shape host buffers. Correct inference follows those error cases.
The C++ consumer rejects a write beyond its packed tensor size, then verifies
that the same buffer still accepts valid inputs. It owns handles through RAII.

Include `tests/runtime.cmake` after defining the LiteRT targets. It uses
`EMBER_LITERT_SOURCE_DIR`, `EMBER_HOST_FLATC` and the generated configuration
under `${CMAKE_BINARY_DIR}/include`.

```sh
cmake --build "$build" --target ember-litert-runtime-tests --parallel
```

The target compiles both consumers and generates
`$build/runtime-testdata/runtime-add.tflite`. CTest entries `litert-cpu-c` and
`litert-cpu-cpp` run only on the target architecture, either natively or with
an explicitly configured cross emulator. Cross compilation alone does not
establish runtime acceptance.

The `EmberLiteRt` installation component places consumers in
`libexec/ember-litert` and the fixture in `share/ember-litert`. For a `/usr/pkg`
installation, run on the target:

```sh
/usr/pkg/libexec/ember-litert/ember-litert-runtime-c \
    /usr/pkg/share/ember-litert/runtime-add.tflite
/usr/pkg/libexec/ember-litert/ember-litert-runtime-cpp \
    /usr/pkg/share/ember-litert/runtime-add.tflite
```

These checks establish CPU arithmetic, public-consumer linkage and selected
error contracts. They do not establish model coverage, accelerator support,
performance or sustained operation.

// SPDX-License-Identifier: MIT
#include <cstdlib>
#include <iostream>
#include <string>

#include "litert/cc/litert_compiled_model.h"
#include "litert/cc/litert_environment.h"
#include "litert/cc/litert_environment_options.h"
#include "runtime-vectors.h"

template <typename T>
void Check(const litert::Expected<T>& result, const char* operation) {
  if (!result) {
    std::cerr << "FAIL: " << operation << ": " << result.Error().Message() << '\n';
    std::exit(EXIT_FAILURE);
  }
}

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " runtime-add.tflite\n";
    return 2;
  }
  const litert::EnvironmentOptions env_options({});
  auto env = litert::Environment::Create(env_options);
  Check(env, "create C++ environment");
  auto model = litert::CompiledModel::Create(
      *env, std::string(argv[1]), litert::HwAccelerators::kCpu);
  Check(model, "compile C++ CPU model");
  auto inputs = model->CreateInputBuffers();
  auto outputs = model->CreateOutputBuffers();
  Check(inputs, "create C++ inputs");
  Check(outputs, "create C++ outputs");
  if (inputs->size() != 2 || outputs->size() != 1) {
    std::cerr << "FAIL: unexpected fixture input/output count\n";
    return EXIT_FAILURE;
  }
  auto packed_bytes = (*inputs)[0].PackedSize();
  Check(packed_bytes, "query C++ input packed size");
  if (*packed_bytes != sizeof(runtime_x[0])) {
    std::cerr << "FAIL: fixture packed size must be four floats\n";
    return EXIT_FAILURE;
  }
  // Write checks PackedSize(), so XNNPACK allocation padding is not writable.
  const float too_large[5] = {};
  if ((*inputs)[0].Write<float>(litert::Span<const float>(too_large, 5))) {
    std::cerr << "FAIL: C++ buffer accepted an oversized write\n";
    return EXIT_FAILURE;
  }
  for (int n = 0; n < kRuntimeCases; ++n) {
    Check((*inputs)[0].Write<float>(
              litert::Span<const float>(runtime_x[n], kRuntimeElements)),
          "write first C++ input");
    Check((*inputs)[1].Write<float>(
              litert::Span<const float>(runtime_y[n], kRuntimeElements)),
          "write second C++ input");
    Check(model->Run(*inputs, *outputs), "run C++ CPU model");
    float actual[kRuntimeElements];
    Check((*outputs)[0].Read<float>(litert::Span<float>(actual, kRuntimeElements)),
          "read C++ output");
    for (int i = 0; i < kRuntimeElements; ++i) {
      if (actual[i] != runtime_sum[n][i]) {
        std::cerr << "FAIL: C++ run " << n << " element " << i << ": "
                  << actual[i] << ", expected " << runtime_sum[n][i] << '\n';
        return EXIT_FAILURE;
      }
    }
  }
  std::cout << "PASS: C++ CPU ADD, 3 changed input pairs, 12 exact sums; "
               "oversized-write recovery\n";
  return EXIT_SUCCESS;
}

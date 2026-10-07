// SPDX-License-Identifier: MIT
// A real LiteRT-LM Engine API consumer. No model output is synthesized here.
#include <charconv>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "runtime/engine/engine.h"
#include "runtime/engine/engine_factory.h"
#include "runtime/engine/engine_settings.h"
#include "runtime/engine/io_types.h"
#include "runtime/executor/executor_settings_base.h"
#include "runtime/executor/llm_executor_settings.h"
#include "runtime/proto/sampler_params.pb.h"

namespace {
using namespace litert::lm;

absl::StatusOr<std::unique_ptr<Engine>> Open(const std::string& path,
                                           int threads) {
  auto assets = ModelAssets::Create(path);
  if (!assets.ok()) return assets.status();
  auto settings = EngineSettings::CreateDefault(std::move(*assets), Backend::CPU,
                                               std::nullopt, std::nullopt,
                                               Backend::CPU);
  if (!settings.ok()) return settings.status();
  auto& executor = settings->GetMutableMainExecutorSettings();
  auto configured_cpu = executor.GetBackendConfig<CpuConfig>();
  if (!configured_cpu.ok()) return configured_cpu.status();
  CpuConfig cpu = *configured_cpu;
  cpu.number_of_threads = threads;
  executor.SetBackendConfig(cpu);
  // Disk-backed packed weights are opt-in; the caller owns their lifecycle.
  const char* cache_dir = std::getenv("EMBER_LITERT_CACHE_DIR");
  executor.SetCacheDir(cache_dir != nullptr && cache_dir[0] != '\0'
                           ? cache_dir : ":nocache");
  return EngineFactory::CreateDefault(std::move(*settings));
}

absl::StatusOr<Responses> Run(Engine& engine, const std::string& prompt,
                             int max_tokens) {
  auto config = SessionConfig::CreateDefault();
  // The CPU factory implements TOP_P; k=1 is exact argmax selection.
  config.GetMutableSamplerParams().set_type(proto::SamplerParameters::TOP_P);
  config.GetMutableSamplerParams().set_k(1);
  config.GetMutableSamplerParams().set_p(1.0f);
  config.GetMutableSamplerParams().set_temperature(1.0f);
  config.GetMutableSamplerParams().set_seed(42);
  config.SetSamplerBackend(Backend::CPU);
  config.SetMaxOutputTokens(max_tokens);
  // Engine API takes a raw prompt. Conversation/Jinja formatting is a distinct
  // upstream API and is deliberately not claimed by this profile.
  config.SetApplyPromptTemplateInSession(false);
  auto session = engine.CreateSession(config);
  if (!session.ok()) return session.status();
  std::vector<InputData> input;
  input.emplace_back(InputText(prompt));
  auto status = (*session)->RunPrefill(input);
  if (!status.ok()) return status;
  return (*session)->RunDecode();
}

bool Positive(std::string_view value, int& result, int upper) {
  auto parsed = std::from_chars(value.data(), value.data() + value.size(), result);
  return parsed.ec == std::errc{} && parsed.ptr == value.data() + value.size() &&
         result > 0 && result <= upper;
}

int Fail(const absl::Status& status) {
  std::cerr << status << '\n';
  return 1;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 3 || argc > 6) {
    std::cerr << "Usage: ember-litert-lm infer|verify MODEL [PROMPT [TOKENS [THREADS]]]\n"
                 "       ember-litert-lm reject MODEL\n";
    return 2;
  }
  const std::string mode = argv[1];
  if (mode != "infer" && mode != "verify" && mode != "reject") return 2;
  if (mode == "reject" && argc != 3) return 2;
  int tokens = 16, threads = 2;
  if ((argc > 4 && !Positive(argv[4], tokens, 4096)) ||
      (argc > 5 && !Positive(argv[5], threads, 64))) return 2;
  const std::string prompt = argc > 3 ? argv[3] : "Hello world!";
  const auto registered = EngineFactory::Instance().ListEngineTypes();
  if (!registered.ok() || registered->empty()) {
    std::cerr << "FAIL: production engine registration is missing\n";
    return 1;
  }
  auto start = std::chrono::steady_clock::now();
  auto engine = Open(argv[2], threads);
  if (mode == "reject") {
    if (engine.ok()) {
      std::cerr << "FAIL: invalid model was accepted\n";
      return 1;
    }
    std::cout << "PASS: model rejected: " << engine.status() << '\n';
    return 0;
  }
  if (!engine.ok()) return Fail(engine.status());
  auto result = Run(**engine, prompt, tokens);
  if (!result.ok()) return Fail(result.status());
  if (result->GetTexts().size() != 1 || result->GetTexts()[0].empty() ||
      result->GetTokenIds().size() != 1 || result->GetTokenIds()[0].empty()) {
    std::cerr << "FAIL: inference did not return nonempty text and token IDs\n";
    return 1;
  }
  if (mode == "verify") {
    auto repeated = Run(**engine, prompt, tokens);
    if (!repeated.ok()) return Fail(repeated.status());
    if (result->GetTexts() != repeated->GetTexts() ||
        result->GetTokenIds() != repeated->GetTokenIds()) {
      std::cerr << "FAIL: independent greedy sessions differ\n";
      return 1;
    }
    std::cout << "PASS: two independent greedy sessions agree\n";
  }
  const double seconds = std::chrono::duration<double>(
      std::chrono::steady_clock::now() - start).count();
  std::cout << result->GetTexts()[0] << '\n';
  std::cout << "tokens=" << result->GetTokenIds()[0].size()
            << " elapsed_seconds=" << seconds << " backend=CPU\n";
  return 0;
}

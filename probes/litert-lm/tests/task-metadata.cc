// SPDX-License-Identifier: MIT
// Exercise the production Task loader, executor error paths and KV allocator.
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

#include "absl/status/status.h"
#include "litert/cc/litert_compiled_model.h"
#include "litert/cc/litert_environment.h"
#include "minizip/zip.h"
#include "runtime/components/model_resources_task.h"
#include "runtime/executor/litert/state.h"
#include "runtime/executor/llm_litert_compiled_model_executor.h"
#include "runtime/util/memory_mapped_file.h"
#include "runtime/util/model_asset_bundle_resources.h"

namespace {
using namespace litert::lm;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

struct Scratch {
  std::string path;
  Scratch() {
    const char* tmp = std::getenv("TMPDIR");
    path = std::string(tmp != nullptr ? tmp : "/tmp") +
           "/ember-task-metadata.XXXXXX";
    Require(mkdtemp(path.data()) != nullptr, "create scratch directory");
  }
  ~Scratch() {
    std::error_code error;
    std::filesystem::remove_all(path, error);
  }
};

void AddMember(zipFile archive, const char* name, const std::string& bytes) {
  Require(zipOpenNewFileInZip(archive, name, nullptr, nullptr, 0, nullptr, 0,
                             nullptr, 0, 0) == ZIP_OK,
          "create stored ZIP member");
  Require(zipWriteInFileInZip(archive, bytes.data(), bytes.size()) == ZIP_OK,
          "write ZIP member");
  Require(zipCloseFileInZip(archive) == ZIP_OK, "close ZIP member");
}

void WriteTask(const std::string& path, const std::string& model,
               const std::optional<std::string>& metadata) {
  zipFile archive = zipOpen(path.c_str(), APPEND_STATUS_CREATE);
  Require(archive != nullptr, "create Task archive");
  AddMember(archive, "TF_LITE_PREFILL_DECODE", model);
  if (metadata) AddMember(archive, "EXECUTOR_METADATA", *metadata);
  Require(zipClose(archive, nullptr) == ZIP_OK, "close Task archive");
}

std::unique_ptr<ModelResources> OpenTask(const std::string& path) {
  auto mapping = MemoryMappedFile::Create(path);
  Require(mapping.ok(), "map Task archive");
  auto bundle = ModelAssetBundleResources::Create(
      "executor-metadata-contract",
      std::shared_ptr<MemoryMappedFile>(std::move(*mapping)));
  Require(bundle.ok(), "read Task archive");
  auto resources = ModelResourcesTask::Create(std::move(*bundle));
  Require(resources.ok(), "create Task resources");
  return std::move(*resources);
}

LlmExecutorSettings Settings(const std::string& path) {
  auto assets = ModelAssets::Create(path);
  Require(assets.ok(), "open executor model assets");
  auto settings = LlmExecutorSettings::CreateDefault(std::move(*assets));
  Require(settings.ok(), "create CPU executor settings");
  settings->SetCacheDir(":nocache");
  return std::move(*settings);
}

void RejectedByExecutors(const std::string& path, litert::Environment& env) {
  auto resources = OpenTask(path);
  auto metadata = resources->GetExecutorMetadata();
  Require(!metadata.ok() && absl::IsInvalidArgument(metadata.status()),
          "malformed present metadata must be InvalidArgument");
  // These are the actual static/dynamic executor entry points. Returning some
  // later graph/signature error is not sufficient: preserve the parser error.
  auto fixed = LlmLiteRtCompiledModelExecutorStatic::Create(
      Settings(path), env, *resources);
  Require(!fixed.ok() && fixed.status() == metadata.status(),
          "static executor swallowed malformed metadata");
  auto dynamic = LlmLiteRtCompiledModelExecutorDynamic::Create(
      Settings(path), env, *resources);
  Require(!dynamic.ok() && dynamic.status() == metadata.status(),
          "dynamic executor swallowed malformed metadata");
}

void CheckState(const std::string& path, litert::Environment& env,
                bool has_metadata, int expected_entries) {
  auto resources = OpenTask(path);
  auto metadata = resources->GetExecutorMetadata();
  if (has_metadata) {
    Require(metadata.ok(), "load explicit ExecutorMetadata");
    Require(resources->GetExecutorMetadata().value() == *metadata,
            "metadata cache must retain pointer identity");
  } else {
    Require(!metadata.ok() && absl::IsNotFound(metadata.status()),
            "absent metadata must be NotFound");
  }
  auto buffer = resources->GetTFLiteModelBuffer(ModelType::kTfLitePrefillDecode);
  Require(buffer.ok(), "read state model");
  auto compiled = litert::CompiledModel::Create(
      env, litert::BufferRef<uint8_t>(buffer->data(), buffer->size()),
      litert::HwAccelerators::kCpu);
  Require(static_cast<bool>(compiled), "compile state fixture on CPU");
  auto state = LitertState::Create(
      env, *compiled, "decode", has_metadata ? *metadata : nullptr,
      LitertState::AllocationPolicy::kInplace, 1);
  if (!state.ok()) std::cerr << state.status() << '\n';
  Require(state.ok(), "allocate real LitertState");
  Require((*state)->GetNumEntries() == expected_entries,
          "KV context size does not match selected sequence axis");
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "Usage: ember-task-metadata-test task-state.tflite\n";
    return 2;
  }
  try {
    std::ifstream input(argv[1], std::ios::binary);
    Require(input.good(), "open state fixture");
    const std::string model((std::istreambuf_iterator<char>(input)), {});
    Require(!model.empty(), "state fixture must not be empty");
    Scratch scratch;
    auto environment = litert::Environment::Create({});
    Require(static_cast<bool>(environment), "create LiteRT environment");
    proto::ExecutorMetadata metadata;
    for (const char* name : {"kv_cache_k_0", "kv_cache_v_0"}) {
      auto* state = metadata.mutable_llm_executor_metadata()->add_state_buffers();
      state->set_prefill_input_name(name);
      state->set_prefill_output_name(name);
      state->set_decode_input_name(name);
      state->set_decode_output_name(name);
      state->set_type(name[9] == 'k' ? proto::StateBuffer::TYPE_GLOBAL_KEY_CACHE
                                    : proto::StateBuffer::TYPE_GLOBAL_VALUE_CACHE);
      state->set_sequence_axis(1);
    }
    const std::string valid = scratch.path + "/valid.task";
    WriteTask(valid, model, metadata.SerializeAsString());
    CheckState(valid, *environment, true, 1280);
    const std::string absent = scratch.path + "/absent.task";
    WriteTask(absent, model, std::nullopt);
    CheckState(absent, *environment, false, 4);
    for (const std::string& bytes : {std::string("\xff", 1), std::string()}) {
      const std::string broken = scratch.path + "/broken.task";
      WriteTask(broken, model, bytes);
      RejectedByExecutors(broken, *environment);
    }
    std::cout << "PASS: Task explicit KV axis gives context 1280; absent metadata "
                 "retains heuristic; malformed/empty metadata rejected by both executors\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}

# SPDX-License-Identifier: MIT
# Included by the common LiteRT CPU source profile; never downloads dependencies.
cmake_minimum_required(VERSION 3.25)

foreach(var EMBER_LITERT_LM_SOURCE_DIR EMBER_LITERT_SOURCE_DIR
            EMBER_HOST_PROTOC EMBER_HOST_FLATC)
  if(NOT EXISTS "${${var}}")
    message(FATAL_ERROR "${var} must name an existing source directory or host tool")
  endif()
endforeach()
if(NOT TARGET minizip)
  if(NOT EXISTS "${EMBER_MINIZIP_SOURCE_DIR}/unzip.c")
    message(FATAL_ERROR "EMBER_MINIZIP_SOURCE_DIR must name zlib 1.3.2 contrib/minizip")
  endif()
  get_filename_component(_minizip_parent "${EMBER_MINIZIP_SOURCE_DIR}" DIRECTORY)
  add_library(minizip STATIC
    "${EMBER_MINIZIP_SOURCE_DIR}/ioapi.c"
    "${EMBER_MINIZIP_SOURCE_DIR}/unzip.c"
    "${EMBER_MINIZIP_SOURCE_DIR}/zip.c")
  target_include_directories(minizip PUBLIC "${_minizip_parent}")
  target_link_libraries(minizip PUBLIC ZLIB::ZLIB)
endif()
foreach(dep litert_runtime tensorflow-lite protobuf::libprotobuf re2::re2
            sentencepiece-static flatbuffers::flatbuffers
            nlohmann_json::nlohmann_json ZLIB::ZLIB minizip Eigen3::Eigen)
  if(NOT TARGET ${dep})
    message(FATAL_ERROR "LiteRT-LM requires the common dependency target ${dep}")
  endif()
endforeach()

# Add the missing upstream custom op without modifying the common LiteRT tree.
# The four added files retain their exact upstream bytes and Apache-2.0 notices.
find_program(EMBER_PATCH_EXECUTABLE patch REQUIRED)
set(_lm_backport "${CMAKE_CURRENT_BINARY_DIR}/gated-delta-backport")
file(REMOVE_RECURSE "${_lm_backport}")
file(MAKE_DIRECTORY "${_lm_backport}")
execute_process(COMMAND "${EMBER_PATCH_EXECUTABLE}" -p1
  WORKING_DIRECTORY "${_lm_backport}"
  INPUT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/patches/litert-2.2-gated-delta-net.patch"
  RESULT_VARIABLE _patch_result OUTPUT_QUIET ERROR_VARIABLE _patch_error)
if(NOT _patch_result EQUAL 0)
  message(FATAL_ERROR "GatedDeltaNet backport failed: ${_patch_error}")
endif()
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/patches/gated-delta-upstream.sha256"
  _gated_checksums REGEX "^[a-f0-9]+  ")
foreach(entry IN LISTS _gated_checksums)
  string(REGEX REPLACE "^([a-f0-9]+)  (.*)$" "\\1" expected "${entry}")
  string(REGEX REPLACE "^([a-f0-9]+)  (.*)$" "\\2" path "${entry}")
  file(SHA256 "${_lm_backport}/${path}" actual)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "GatedDeltaNet upstream checksum mismatch: ${path}")
  endif()
endforeach()
set(_gated_dir "${_lm_backport}/litert/experimental/custom_ops/gated_delta_net")
add_library(ember_litert_lm_gated_delta STATIC
  "${_gated_dir}/gated_delta_update_impl.cc"
  "${_gated_dir}/gated_delta_update_litert_custom_op.cc")
target_compile_features(ember_litert_lm_gated_delta PUBLIC cxx_std_20)
target_include_directories(ember_litert_lm_gated_delta PUBLIC "${_lm_backport}")
target_link_libraries(ember_litert_lm_gated_delta PUBLIC
  litert_runtime flatbuffers::flatbuffers Eigen3::Eigen)

set(_lm_generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${_lm_generated}/runtime/proto"
                    "${_lm_generated}/runtime/util"
                    "${_lm_generated}/schema/core")
set(_lm_protos
  runtime/proto/asr_metadata.proto runtime/proto/asr_model_type.proto
  runtime/proto/embedding_metadata.proto runtime/proto/embedding_model_type.proto
  runtime/proto/engine.proto runtime/proto/executor_metadata.proto
  runtime/proto/litert_lm_metrics.proto runtime/proto/llm_metadata.proto
  runtime/proto/llm_model_type.proto runtime/proto/sampler_params.proto
  runtime/proto/token.proto runtime/proto/tts_metadata.proto
  runtime/proto/tts_model_type.proto runtime/util/external_file.proto)
set(_lm_proto_inputs)
set(_lm_proto_outputs)
set(_lm_proto_sources)
foreach(proto IN LISTS _lm_protos)
  list(APPEND _lm_proto_inputs "${EMBER_LITERT_LM_SOURCE_DIR}/${proto}")
  string(REGEX REPLACE "\\.proto$" ".pb" base "${proto}")
  list(APPEND _lm_proto_outputs "${_lm_generated}/${base}.cc"
                               "${_lm_generated}/${base}.h")
  list(APPEND _lm_proto_sources "${_lm_generated}/${base}.cc")
endforeach()
add_custom_command(OUTPUT ${_lm_proto_outputs}
  COMMAND "${EMBER_HOST_PROTOC}" "--proto_path=${EMBER_LITERT_LM_SOURCE_DIR}"
          "--cpp_out=${_lm_generated}" ${_lm_proto_inputs}
  DEPENDS ${_lm_proto_inputs} "${EMBER_HOST_PROTOC}" VERBATIM)
set(_lm_fbs "${EMBER_LITERT_LM_SOURCE_DIR}/schema/core/litertlm_header_schema.fbs")
set(_lm_fbs_output "${_lm_generated}/schema/core/litertlm_header_schema_generated.h")
add_custom_command(OUTPUT "${_lm_fbs_output}"
  COMMAND "${EMBER_HOST_FLATC}" --cpp --gen-object-api --reflect-names --gen-mutable
          -o "${_lm_generated}/schema/core" "${_lm_fbs}"
  DEPENDS "${_lm_fbs}" "${EMBER_HOST_FLATC}" VERBATIM)
add_custom_target(ember_litert_lm_generated
  DEPENDS ${_lm_proto_outputs} "${_lm_fbs_output}")

include(cmake/sources.cmake)
set(_lm_overlay "${CMAKE_CURRENT_BINARY_DIR}/lm-source-overlay")
set(_lm_sources)
foreach(src IN LISTS EMBER_LM_SOURCES)
  configure_file("${EMBER_LITERT_LM_SOURCE_DIR}/${src}" "${_lm_overlay}/${src}" COPYONLY)
  list(APPEND _lm_sources "${_lm_overlay}/${src}")
endforeach()
foreach(patch lm-litert-2.2-options.patch lm-cpu-sampler-build.patch
              lm-task-executor-metadata.patch)
  execute_process(COMMAND "${EMBER_PATCH_EXECUTABLE}" -p1
    WORKING_DIRECTORY "${_lm_overlay}"
    INPUT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/patches/${patch}"
    RESULT_VARIABLE _patch_result OUTPUT_QUIET ERROR_VARIABLE _patch_error)
  if(NOT _patch_result EQUAL 0)
    message(FATAL_ERROR "LiteRT-LM patch ${patch} failed: ${_patch_error}")
  endif()
endforeach()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/patches/lm-litert-2.2-options.patch"
  "${CMAKE_CURRENT_SOURCE_DIR}/patches/lm-cpu-sampler-build.patch"
  "${CMAKE_CURRENT_SOURCE_DIR}/patches/lm-task-executor-metadata.patch"
  "${CMAKE_CURRENT_SOURCE_DIR}/patches/litert-2.2-gated-delta-net.patch")

# An OBJECT library retains EngineFactory registration without platform-specific
# whole-archive flags. It contains upstream engine code, not an engine substitute.
add_library(ember_litert_lm_cpu OBJECT ${_lm_sources} ${_lm_proto_sources})
add_dependencies(ember_litert_lm_cpu ember_litert_lm_generated)
target_compile_features(ember_litert_lm_cpu PUBLIC cxx_std_20)
target_compile_definitions(ember_litert_lm_cpu PUBLIC
  LITERT_LM_VERSION_STRING="0.18.0"
  ENABLE_SENTENCEPIECE_TOKENIZER=1
  LITERT_DISABLE_GPU LITERT_DISABLE_NPU)
target_include_directories(ember_litert_lm_cpu PUBLIC
  "${_lm_generated}" "${EMBER_LITERT_LM_SOURCE_DIR}" "${EMBER_LITERT_SOURCE_DIR}")
target_link_libraries(ember_litert_lm_cpu PUBLIC
  litert_runtime ember_litert_lm_gated_delta tensorflow-lite protobuf::libprotobuf re2::re2
  sentencepiece-static flatbuffers::flatbuffers nlohmann_json::nlohmann_json
  ZLIB::ZLIB minizip
  absl::algorithm_container absl::any_invocable absl::check absl::cleanup
  absl::flat_hash_map absl::flat_hash_set absl::log absl::log_globals
  absl::memory absl::random_random absl::status absl::statusor absl::str_format
  absl::strings absl::synchronization absl::time)

add_executable(ember-litert-lm tests/engine-cli.cc)
target_link_libraries(ember-litert-lm PRIVATE ember_litert_lm_cpu)
set_target_properties(ember-litert-lm ember_litert_lm_cpu
  PROPERTIES CXX_EXTENSIONS OFF)
install(TARGETS ember-litert-lm RUNTIME DESTINATION bin COMPONENT EmberLiteRt)

add_library(ember_litert_lm_header_contract OBJECT tests/cxx-headers.cc)
target_compile_features(ember_litert_lm_header_contract PRIVATE cxx_std_20)
set_target_properties(ember_litert_lm_header_contract PROPERTIES CXX_EXTENSIONS OFF)
target_link_libraries(ember_litert_lm_header_contract PRIVATE litert_runtime)
add_dependencies(ember-litert-lm ember_litert_lm_header_contract)

add_executable(ember-gated-delta-test tests/gated-delta.cc)
target_link_libraries(ember-gated-delta-test PRIVATE ember_litert_lm_gated_delta)
install(TARGETS ember-gated-delta-test RUNTIME DESTINATION bin COMPONENT EmberLiteRt)

add_executable(ember-task-metadata-test tests/task-metadata.cc)
target_link_libraries(ember-task-metadata-test PRIVATE ember_litert_lm_cpu)
set(_state_model "${_lm_generated}/task-state.tflite")
set(_state_schema "${EMBER_LITERT_SOURCE_DIR}/tflite/converter/schema/schema.fbs")
add_custom_command(OUTPUT "${_state_model}"
  COMMAND "${EMBER_HOST_FLATC}" --binary -o "${_lm_generated}"
          "${_state_schema}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/task-state.json"
  DEPENDS "${_state_schema}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/task-state.json"
          "${EMBER_HOST_FLATC}" VERBATIM)
add_custom_target(ember_task_state_fixture DEPENDS "${_state_model}")
add_dependencies(ember-task-metadata-test ember_task_state_fixture)
add_dependencies(ember-litert-lm ember-task-metadata-test)
install(TARGETS ember-task-metadata-test RUNTIME DESTINATION bin
  COMPONENT EmberLiteRt)
install(FILES "${_state_model}" DESTINATION share/ember-litert
  COMPONENT EmberLiteRt)

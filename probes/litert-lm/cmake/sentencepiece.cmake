# SPDX-License-Identifier: MIT
# Upstream SentencePiece processor with shared Abseil/protobuf and host protoc.
# Call before adding the LM directory when building dependencies from source.
function(ember_add_sentencepiece source_dir)
  if(TARGET sentencepiece-static)
    message(FATAL_ERROR "sentencepiece-static already exists")
  endif()
  file(STRINGS "${source_dir}/VERSION.txt" _sp_version LIMIT_COUNT 1)
  if(NOT _sp_version STREQUAL "0.2.2")
    message(FATAL_ERROR "This source recipe requires SentencePiece 0.2.2")
  endif()
  set(_sp_dir "${CMAKE_CURRENT_BINARY_DIR}/sentencepiece-common")
  file(MAKE_DIRECTORY "${_sp_dir}")
  set(_sp_units bpe_model char_model filesystem init model_factory model_interface
    normalizer sentencepiece_processor unigram_model util word_model)
  file(GLOB _sp_headers "${source_dir}/src/*.h")
  set(_sp_inputs ${_sp_headers})
  set(_sp_sources)
  foreach(unit IN LISTS _sp_units)
    list(APPEND _sp_inputs "${source_dir}/src/${unit}.cc")
    list(APPEND _sp_sources "${_sp_dir}/${unit}.cc")
  endforeach()
  # Same include canonicalization as LiteRT-LM's SentencePiece WORKSPACE rule.
  # Overlay keeps downloaded inputs intact and cannot select bundled Abseil.
  foreach(input IN LISTS _sp_inputs)
    get_filename_component(name "${input}" NAME)
    file(READ "${input}" content)
    string(REPLACE "\"third_party/absl/" "\"absl/" content "${content}")
    set(previous "")
    if(EXISTS "${_sp_dir}/${name}")
      file(READ "${_sp_dir}/${name}" previous)
    endif()
    if(NOT content STREQUAL previous)
      file(WRITE "${_sp_dir}/${name}" "${content}")
    endif()
  endforeach()
  set(PROJECT_VERSION "0.2.2")
  set(PROJECT_NAME "sentencepiece")
  set(INSTALL_DATADIR "${CMAKE_INSTALL_PREFIX}/share/sentencepiece")
  configure_file("${source_dir}/config.h.in" "${_sp_dir}/config.h" @ONLY)
  set(_sp_proto_outputs)
  foreach(proto sentencepiece sentencepiece_model)
    list(APPEND _sp_proto_outputs "${_sp_dir}/${proto}.pb.cc" "${_sp_dir}/${proto}.pb.h")
    list(APPEND _sp_sources "${_sp_dir}/${proto}.pb.cc")
  endforeach()
  add_custom_command(OUTPUT ${_sp_proto_outputs}
    COMMAND "${EMBER_HOST_PROTOC}" "--proto_path=${source_dir}/src"
      "--cpp_out=${_sp_dir}" "${source_dir}/src/sentencepiece.proto"
      "${source_dir}/src/sentencepiece_model.proto"
    DEPENDS "${EMBER_HOST_PROTOC}" "${source_dir}/src/sentencepiece.proto"
      "${source_dir}/src/sentencepiece_model.proto" VERBATIM)
  add_custom_target(ember_sentencepiece_generated DEPENDS ${_sp_proto_outputs})
  add_library(sentencepiece-static STATIC ${_sp_sources})
  add_dependencies(sentencepiece-static ember_sentencepiece_generated)
  target_compile_features(sentencepiece-static PUBLIC cxx_std_20)
  target_compile_definitions(sentencepiece-static PUBLIC _USE_EXTERNAL_PROTOBUF)
  target_include_directories(sentencepiece-static PUBLIC "${_sp_dir}"
    PRIVATE "${source_dir}" "${source_dir}/third_party")
  target_link_libraries(sentencepiece-static PUBLIC protobuf::libprotobuf
    absl::status absl::status_builder absl::strings absl::flags absl::flags_parse
    absl::log absl::log_initialize absl::check absl::random_random absl::time)
endfunction()

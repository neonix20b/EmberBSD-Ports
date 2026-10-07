# SPDX-License-Identifier: MIT
# Include after the LiteRT subdirectory. No target tools execute on the host.
if(NOT TARGET litert_runtime_c_api_shared_lib)
  message(FATAL_ERROR "Runtime acceptance tests require shared libLiteRt")
endif()
if(NOT EXISTS "${EMBER_HOST_FLATC}")
  message(FATAL_ERROR "Set EMBER_HOST_FLATC to the native host flatc executable")
endif()
set(_runtime_tests "${CMAKE_CURRENT_LIST_DIR}")
set(_runtime_model_dir "${CMAKE_CURRENT_BINARY_DIR}/runtime-testdata")
set(_runtime_model "${_runtime_model_dir}/runtime-add.tflite")
set(_runtime_schema "${EMBER_LITERT_SOURCE_DIR}/tflite/converter/schema/schema.fbs")
add_custom_command(OUTPUT "${_runtime_model}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${_runtime_model_dir}"
  COMMAND "${EMBER_HOST_FLATC}" --binary --strict-json
          -o "${_runtime_model_dir}" "${_runtime_schema}"
          "${_runtime_tests}/runtime-add.json"
  DEPENDS "${_runtime_tests}/runtime-add.json" "${_runtime_schema}"
          "${EMBER_HOST_FLATC}"
  VERBATIM)
add_custom_target(ember-litert-runtime-fixture DEPENDS "${_runtime_model}")
add_executable(ember-litert-runtime-c "${_runtime_tests}/runtime-c.c")
add_executable(ember-litert-runtime-cpp "${_runtime_tests}/runtime-cpp.cc")
target_compile_features(ember-litert-runtime-c PRIVATE c_std_11)
target_compile_features(ember-litert-runtime-cpp PRIVATE cxx_std_20)
target_compile_definitions(ember-litert-runtime-cpp PRIVATE LITERT_NO_ABSL)
foreach(_consumer ember-litert-runtime-c ember-litert-runtime-cpp)
  target_include_directories(${_consumer} PRIVATE
    "${EMBER_LITERT_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/include")
  target_link_libraries(${_consumer} PRIVATE litert_runtime_c_api_shared_lib)
  set_target_properties(${_consumer} PROPERTIES
    INSTALL_RPATH "$ORIGIN/../../lib;/usr/pkg/gcc16/lib")
  add_dependencies(${_consumer} ember-litert-runtime-fixture)
endforeach()
add_custom_target(ember-litert-runtime-tests
  DEPENDS ember-litert-runtime-c ember-litert-runtime-cpp)
# CTest executes only on a native build or through an explicit cross emulator.
enable_testing()
add_test(NAME litert-cpu-c COMMAND ember-litert-runtime-c "${_runtime_model}")
add_test(NAME litert-cpu-cpp COMMAND ember-litert-runtime-cpp "${_runtime_model}")
set_tests_properties(litert-cpu-c litert-cpu-cpp PROPERTIES TIMEOUT 60)
include(GNUInstallDirs)
install(TARGETS ember-litert-runtime-c ember-litert-runtime-cpp
  RUNTIME DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/ember-litert"
  COMPONENT EmberLiteRt)
install(FILES "${_runtime_model}"
  DESTINATION "${CMAKE_INSTALL_DATADIR}/ember-litert"
  COMPONENT EmberLiteRt)

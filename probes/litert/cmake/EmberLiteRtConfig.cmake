# SPDX-License-Identifier: MIT
get_filename_component(_ember_litert_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(NOT TARGET EmberLiteRt::Runtime)
  add_library(EmberLiteRt::Runtime SHARED IMPORTED)
  set_target_properties(EmberLiteRt::Runtime PROPERTIES
    IMPORTED_LOCATION "${_ember_litert_prefix}/lib/libLiteRt.so"
    INTERFACE_INCLUDE_DIRECTORIES "${_ember_litert_prefix}/include"
    INTERFACE_COMPILE_DEFINITIONS LITERT_NO_ABSL)
endif()
unset(_ember_litert_prefix)

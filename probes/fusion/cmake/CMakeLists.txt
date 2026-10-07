# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.16)
project(EmberFusion VERSION 1.3.3 LANGUAGES C)
include(CMakePackageConfigHelpers)
if(NOT IS_ABSOLUTE "${FUSION_SOURCE}" OR NOT EXISTS "${FUSION_SOURCE}/Fusion/Fusion.h")
  message(FATAL_ERROR "FUSION_SOURCE must name the verified Fusion 1.3.3 source tree")
endif()
# The upstream native target is retained; the top-level examples and Python
# wrapper are unnecessary for this installed C library profile.
set(BUILD_SHARED_LIBS ON)
add_subdirectory("${FUSION_SOURCE}/Fusion" fusion)
set_target_properties(Fusion PROPERTIES
  VERSION "${PROJECT_VERSION}" SOVERSION "${PROJECT_VERSION}"
  INTERFACE_INCLUDE_DIRECTORIES
  "$<BUILD_INTERFACE:${FUSION_SOURCE}/Fusion>;$<INSTALL_INTERFACE:include/Fusion>")
install(TARGETS Fusion EXPORT FusionTargets
  LIBRARY DESTINATION lib ARCHIVE DESTINATION lib RUNTIME DESTINATION bin)
install(DIRECTORY "${FUSION_SOURCE}/Fusion/" DESTINATION include/Fusion
  FILES_MATCHING PATTERN "*.h")
install(EXPORT FusionTargets NAMESPACE Fusion:: DESTINATION lib/cmake/Fusion)
configure_package_config_file(FusionConfig.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/FusionConfig.cmake"
  INSTALL_DESTINATION lib/cmake/Fusion)
write_basic_package_version_file("${CMAKE_CURRENT_BINARY_DIR}/FusionConfigVersion.cmake"
  VERSION "${PROJECT_VERSION}" COMPATIBILITY ExactVersion)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/FusionConfig.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/FusionConfigVersion.cmake" DESTINATION lib/cmake/Fusion)

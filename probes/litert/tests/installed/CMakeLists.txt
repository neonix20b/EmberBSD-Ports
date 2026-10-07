# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.24)
project(InstalledLiteRtConsumers LANGUAGES C CXX)
find_package(EmberLiteRt CONFIG REQUIRED)
add_executable(installed-litert-c ../runtime-c.c)
add_executable(installed-litert-cpp ../runtime-cpp.cc)
target_compile_features(installed-litert-c PRIVATE c_std_11)
target_compile_features(installed-litert-cpp PRIVATE cxx_std_20)
set_target_properties(installed-litert-cpp PROPERTIES CXX_EXTENSIONS OFF)
foreach(consumer installed-litert-c installed-litert-cpp)
  target_link_libraries(${consumer} PRIVATE EmberLiteRt::Runtime)
  set_target_properties(${consumer} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "$ORIGIN/../lib;/usr/pkg/gcc16/lib")
endforeach()

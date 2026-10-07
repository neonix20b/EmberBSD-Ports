# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.20)
project(EmberOrbSlam3 VERSION 1.0.0 LANGUAGES C CXX)
include(CMakePackageConfigHelpers)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
option(ORB_SLAM3_HEADLESS "Build without the Pangolin viewer" ON)
if(NOT IS_ABSOLUTE "${ORB_SOURCE}" OR NOT EXISTS "${ORB_SOURCE}/src/System.cc")
  message(FATAL_ERROR "ORB_SOURCE must name the verified and patched v1.0 source tree")
endif()
if(NOT IS_ABSOLUTE "${COMMON_PREFIX}")
  message(FATAL_ERROR "COMMON_PREFIX must name the common Eigen installation")
endif()
set(OPENCV_PREFIX "${COMMON_PREFIX}" CACHE PATH "Selected common OpenCV installation")
if(NOT IS_ABSOLUTE "${OPENCV_PREFIX}")
  message(FATAL_ERROR "OPENCV_PREFIX must name the common OpenCV installation")
endif()
set(Eigen3_DIR "${COMMON_PREFIX}/share/eigen3/cmake")
set(OpenCV_DIR "${OPENCV_PREFIX}/lib/cmake/opencv5")
find_package(Eigen3 5.0.1 EXACT CONFIG REQUIRED NO_DEFAULT_PATH PATHS "${Eigen3_DIR}")
set(opencv_components core imgproc features geometry stereo calib)
if(NOT ORB_SLAM3_HEADLESS)
  list(APPEND opencv_components highgui)
  find_package(Pangolin 0.9.6 CONFIG REQUIRED)
endif()
find_package(OpenCV 5.0.0 EXACT CONFIG REQUIRED COMPONENTS ${opencv_components}
  NO_DEFAULT_PATH PATHS "${OpenCV_DIR}")
find_package(Boost 1.91.0 EXACT CONFIG REQUIRED COMPONENTS serialization)
find_package(OpenSSL 3.5 REQUIRED COMPONENTS Crypto)
find_package(Threads REQUIRED)
get_target_property(eigen_headers Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES)
foreach(path IN ITEMS ${eigen_headers})
  string(FIND "${path}" "${COMMON_PREFIX}/" position)
  if(NOT position EQUAL 0)
    message(FATAL_ERROR "A common dependency escaped COMMON_PREFIX: ${path}")
  endif()
endforeach()
foreach(path IN ITEMS ${OpenCV_INCLUDE_DIRS})
  string(FIND "${path}" "${OPENCV_PREFIX}/" position)
  if(NOT position EQUAL 0)
    message(FATAL_ERROR "OpenCV escaped OPENCV_PREFIX: ${path}")
  endif()
endforeach()

set(dbow_root "${ORB_SOURCE}/Thirdparty/DBoW2")
add_library(DBoW2 SHARED
  "${dbow_root}/DBoW2/BowVector.cpp" "${dbow_root}/DBoW2/FORB.cpp"
  "${dbow_root}/DBoW2/FeatureVector.cpp" "${dbow_root}/DBoW2/ScoringObject.cpp"
  "${dbow_root}/DUtils/Random.cpp" "${dbow_root}/DUtils/Timestamp.cpp")
target_link_libraries(DBoW2 PUBLIC opencv_core Boost::serialization)

set(g2o_root "${ORB_SOURCE}/Thirdparty/g2o")
# This is exactly the source list in the pinned ORB fork, not system g2o.
set(g2o_core hyper_graph_action hyper_graph marginal_covariance_cholesky
  matrix_structure batch_stats parameter cache optimizable_graph solver
  optimization_algorithm_factory estimate_propagator factory sparse_optimizer
  hyper_dijkstra parameter_container optimization_algorithm
  optimization_algorithm_with_hessian optimization_algorithm_levenberg
  optimization_algorithm_gauss_newton jacobian_workspace robust_kernel
  robust_kernel_factory robust_kernel_impl)
set(g2o_sources "${g2o_root}/g2o/types/types_sba.cpp"
  "${g2o_root}/g2o/types/types_six_dof_expmap.cpp"
  "${g2o_root}/g2o/types/types_seven_dof_expmap.cpp"
  "${g2o_root}/g2o/stuff/os_specific.c" "${g2o_root}/g2o/stuff/string_tools.cpp"
  "${g2o_root}/g2o/stuff/property.cpp" "${g2o_root}/g2o/stuff/timeutil.cpp")
foreach(unit IN LISTS g2o_core)
  list(APPEND g2o_sources "${g2o_root}/g2o/core/${unit}.cpp")
endforeach()
set(G2O_SHARED_LIBS 1)
configure_file("${g2o_root}/config.h.in" "${g2o_root}/config.h")
add_library(g2o SHARED ${g2o_sources})
target_compile_definitions(g2o PRIVATE UNIX)
target_link_libraries(g2o PUBLIC Eigen3::Eigen)

set(orb_units System Tracking LocalMapping LoopClosing ORBextractor ORBmatcher
  FrameDrawer Converter MapPoint KeyFrame Atlas Map Optimizer Frame
  KeyFrameDatabase Sim3Solver ImuTypes G2oTypes)
if(NOT ORB_SLAM3_HEADLESS)
  list(APPEND orb_units Viewer MapDrawer)
endif()
set(orb_sources)
foreach(unit IN LISTS orb_units)
  list(APPEND orb_sources "${ORB_SOURCE}/src/${unit}.cc")
endforeach()
list(APPEND orb_sources "${ORB_SOURCE}/src/CameraModels/Pinhole.cpp"
  "${ORB_SOURCE}/src/CameraModels/KannalaBrandt8.cpp"
  "${ORB_SOURCE}/src/OptimizableTypes.cpp" "${ORB_SOURCE}/src/MLPnPsolver.cpp"
  "${ORB_SOURCE}/src/GeometricTools.cc" "${ORB_SOURCE}/src/TwoViewReconstruction.cc"
  "${ORB_SOURCE}/src/Config.cc" "${ORB_SOURCE}/src/Settings.cc")
add_library(ORB_SLAM3 SHARED ${orb_sources})
target_compile_features(ORB_SLAM3 PUBLIC cxx_std_17)
target_compile_definitions(ORB_SLAM3 PRIVATE COMPILEDWITHC11)
if(ORB_SLAM3_HEADLESS)
  target_compile_definitions(ORB_SLAM3 PUBLIC ORB_SLAM3_HEADLESS=1)
else()
  target_include_directories(ORB_SLAM3 PRIVATE ${Pangolin_INCLUDE_DIRS})
  target_link_libraries(ORB_SLAM3 PRIVATE ${Pangolin_LIBRARIES})
endif()
target_link_libraries(ORB_SLAM3 PUBLIC DBoW2 g2o Eigen3::Eigen ${OpenCV_LIBS}
  Boost::serialization Threads::Threads PRIVATE OpenSSL::Crypto)

foreach(target DBoW2 g2o ORB_SLAM3)
  target_include_directories(${target} PUBLIC
    "$<BUILD_INTERFACE:${ORB_SOURCE}>"
    "$<BUILD_INTERFACE:${ORB_SOURCE}/include>"
    "$<BUILD_INTERFACE:${ORB_SOURCE}/include/CameraModels>"
    "$<BUILD_INTERFACE:${ORB_SOURCE}/Thirdparty/Sophus>"
    "$<INSTALL_INTERFACE:include/ORB_SLAM3>"
    "$<INSTALL_INTERFACE:include/ORB_SLAM3/include>"
    "$<INSTALL_INTERFACE:include/ORB_SLAM3/include/CameraModels>"
    "$<INSTALL_INTERFACE:include/ORB_SLAM3/Thirdparty/Sophus>")
  set_target_properties(${target} PROPERTIES VERSION 1.0.0 SOVERSION 1.0.0
    INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib/orb-slam3;${OPENCV_PREFIX}/lib;${COMMON_PREFIX}/lib;/usr/pkg/lib")
  install(TARGETS ${target} EXPORT ORB_SLAM3Targets LIBRARY DESTINATION lib/orb-slam3)
endforeach()
install(DIRECTORY "${ORB_SOURCE}/include/" DESTINATION include/ORB_SLAM3/include
  FILES_MATCHING PATTERN "*.h" PATTERN "Viewer.h" EXCLUDE PATTERN "MapDrawer.h" EXCLUDE)
if(NOT ORB_SLAM3_HEADLESS)
  install(FILES "${ORB_SOURCE}/include/Viewer.h" "${ORB_SOURCE}/include/MapDrawer.h"
    DESTINATION include/ORB_SLAM3/include)
endif()
install(DIRECTORY "${ORB_SOURCE}/Thirdparty/" DESTINATION include/ORB_SLAM3/Thirdparty
  FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp"
  PATTERN "test" EXCLUDE PATTERN "examples" EXCLUDE)
install(EXPORT ORB_SLAM3Targets NAMESPACE ORB_SLAM3:: DESTINATION lib/cmake/ORB_SLAM3)
configure_package_config_file(ORB_SLAM3Config.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/ORB_SLAM3Config.cmake" INSTALL_DESTINATION lib/cmake/ORB_SLAM3)
write_basic_package_version_file("${CMAKE_CURRENT_BINARY_DIR}/ORB_SLAM3ConfigVersion.cmake"
  VERSION 1.0.0 COMPATIBILITY ExactVersion)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/ORB_SLAM3Config.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/ORB_SLAM3ConfigVersion.cmake" DESTINATION lib/cmake/ORB_SLAM3)
install(FILES "${ORB_SOURCE}/Vocabulary/ORBvoc.txt" DESTINATION share/orb-slam3)
install(FILES "${ORB_SOURCE}/Examples/RGB-D/TUM1.yaml" DESTINATION share/orb-slam3/settings)

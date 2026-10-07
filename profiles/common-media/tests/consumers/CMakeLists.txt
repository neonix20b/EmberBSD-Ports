# SPDX-License-Identifier: BSD-2-Clause
# Compile real consumer sources; this is not a full Qt Multimedia/KF package build.
cmake_minimum_required(VERSION 3.29)
project(EmberMediaConsumerAPI VERSION 6.30.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.9 REQUIRED COMPONENTS Core)
qt_standard_project_setup(REQUIRES 6.9)
foreach(source IN ITEMS KFILEMETADATA_SOURCE QTMULTIMEDIA_SOURCE ECM_SOURCE)
    if(NOT IS_DIRECTORY "${${source}}")
        message(FATAL_ERROR "Supply verified ${source}")
    endif()
endforeach()
# Exercise Qt Multimedia's production discovery code, including imported targets.
list(PREPEND CMAKE_MODULE_PATH "${QTMULTIMEDIA_SOURCE}/cmake")
find_package(FFmpeg REQUIRED)
list(APPEND CMAKE_MODULE_PATH "${ECM_SOURCE}/modules")

include(ECMGenerateExportHeader)
include(ECMSetupVersion)
include(ECMQtDeclareLoggingCategory)
ecm_setup_version(PROJECT
    VARIABLE_PREFIX KFILEMETADATA
    VERSION_HEADER "${CMAKE_CURRENT_BINARY_DIR}/kfilemetadata_version.h"
    SOVERSION 3)
ecm_qt_declare_logging_category(debug_sources
    HEADER kfilemetadata_debug.h
    IDENTIFIER KFILEMETADATA_LOG
    CATEGORY_NAME kf.filemetadata)
qt_add_library(metadata-api STATIC
    "${KFILEMETADATA_SOURCE}/src/extractors/ffmpegextractor.cpp"
    "${KFILEMETADATA_SOURCE}/src/extractorplugin.cpp"
    "${KFILEMETADATA_SOURCE}/src/extractionresult.cpp"
    "${KFILEMETADATA_SOURCE}/src/simpleextractionresult.cpp"
    "${KFILEMETADATA_SOURCE}/src/embeddedimagedata.cpp"
    ${debug_sources})
ecm_generate_export_header(metadata-api
    EXPORT_FILE_NAME kfilemetadata_export.h
    BASE_NAME KFileMetaData
    GROUP_BASE_NAME KF
    VERSION 6.30.0
    USE_VERSION_HEADER
    DEPRECATED_BASE_VERSION 0
    DEPRECATION_VERSIONS 6.2 6.12
    EXCLUDE_DEPRECATED_BEFORE_AND_AT 0)
target_include_directories(metadata-api PUBLIC
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${KFILEMETADATA_SOURCE}/src"
    "${KFILEMETADATA_SOURCE}/src/extractors"
    "${QTMULTIMEDIA_SOURCE}/src/plugins/multimedia/ffmpeg")
target_link_libraries(metadata-api PUBLIC Qt6::Core FFmpeg::avcodec FFmpeg::avformat FFmpeg::avutil FFmpeg::swresample FFmpeg::swscale)

qt_add_executable(consumer-api consumer-api.cc)
target_link_libraries(consumer-api PRIVATE metadata-api)

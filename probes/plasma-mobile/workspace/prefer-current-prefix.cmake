# SPDX-License-Identifier: BSD-3-Clause
# Avoid selecting old system headers while validating the current shared prefix.
if(NOT EMBERBSD_PLASMA_PREFIX)
    message(FATAL_ERROR "Set EMBERBSD_PLASMA_PREFIX to the current shared prefix")
endif()
if(IS_DIRECTORY "${EMBERBSD_PLASMA_PREFIX}/include")
    include_directories(BEFORE SYSTEM "${EMBERBSD_PLASMA_PREFIX}/include")
endif()

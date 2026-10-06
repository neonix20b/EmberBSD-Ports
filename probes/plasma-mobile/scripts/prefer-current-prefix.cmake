# SPDX-License-Identifier: BSD-2-Clause
# Prefer current Plasma headers during a temporary private-prefix validation.
if(IS_DIRECTORY "${EMBERBSD_PLASMA_PREFIX}/include")
    include_directories(BEFORE SYSTEM "${EMBERBSD_PLASMA_PREFIX}/include")
endif()

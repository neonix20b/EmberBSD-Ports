# SPDX-License-Identifier: MIT
# Do not use CTest PASS_REGULAR_EXPRESSION: it can override a nonzero exit.
execute_process(COMMAND "${PROFILER}"
    --dry-run --warmup 0 --vlen 31 --iter 1 --tests-substr volk_32f_x2_multiply_32f
    RESULT_VARIABLE status OUTPUT_VARIABLE output ERROR_VARIABLE errors TIMEOUT 20)
message("${output}${errors}")
if(NOT "${status}" STREQUAL "0")
    message(FATAL_ERROR "Profiler did not exit successfully: ${status}")
endif()
string(TOLOWER "${output}${errors}" combined)
if(combined MATCHES "error|exception|fail|no architectures to test")
    message(FATAL_ERROR "Profiler reported an error despite its exit status")
endif()
foreach(required "RUN_VOLK_TESTS: volk_32f_x2_multiply_32f("
    "Best aligned arch" "Best unaligned arch" "Session summary (1 kernels):")
    string(FIND "${output}" "${required}" found)
    if(found EQUAL -1)
        message(FATAL_ERROR "Profiler did not complete the expected kernel: ${required}")
    endif()
endforeach()

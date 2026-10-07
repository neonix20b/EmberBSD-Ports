/* SPDX-License-Identifier: MIT */
#ifndef EMBER_LITERT_RUNTIME_VECTORS_H
#define EMBER_LITERT_RUNTIME_VECTORS_H

enum { kRuntimeCases = 3, kRuntimeElements = 4 };
/* Independent exact arithmetic oracles; all values are binary fractions. */
static const float runtime_x[kRuntimeCases][kRuntimeElements] = {
    {1.0f, 2.0f, -3.0f, 0.25f},
    {-8.0f, 0.0f, 1024.0f, -0.5f},
    {0.5f, 16.0f, 2.0f, -4.0f},
};
static const float runtime_y[kRuntimeCases][kRuntimeElements] = {
    {10.0f, -2.0f, 0.5f, 0.75f},
    {3.0f, 7.0f, -1024.0f, -0.25f},
    {0.25f, -8.0f, -3.0f, 4.0f},
};
static const float runtime_sum[kRuntimeCases][kRuntimeElements] = {
    {11.0f, 0.0f, -2.5f, 1.0f},
    {-5.0f, 7.0f, 0.0f, -0.75f},
    {0.75f, 8.0f, -1.0f, 0.0f},
};
#endif

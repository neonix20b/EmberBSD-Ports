/* SPDX-License-Identifier: BSD-2-Clause */
#ifndef EMBER_GCC_BOUNDARY_H
#define EMBER_GCC_BOUNDARY_H
#include <stdexcept>
#include <string>
std::string transform(const std::string &);
void throw_across(void (*cleanup)());
#endif

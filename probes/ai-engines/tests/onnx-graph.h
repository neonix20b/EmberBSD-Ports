// SPDX-License-Identifier: MIT
#pragma once
#include <cstdint>
#include <string>

using Bytes = std::string;
// Encode this test's fixed ONNX Add/Relu graph without an exporter dependency.
// Field numbers follow ONNX ModelProto, GraphProto, NodeProto and TypeProto.
static Bytes varint(uint64_t value) {
    Bytes result;
    do { unsigned char b = value & 127; value >>= 7; result += char(b | (value ? 128 : 0)); } while (value);
    return result;
}
static Bytes number(unsigned field, uint64_t value) { return varint(field * 8) + varint(value); }
static Bytes message(unsigned field, const Bytes &value) { return varint(field * 8 + 2) + varint(value.size()) + value; }
static Bytes value_info(const char *name) {
    return message(1, name) + message(2, message(1, number(1, 1) + message(2, message(1, number(1, 6)))));
}
static Bytes graph() {
    const Bytes add = message(1, "x") + message(1, "bias") + message(2, "sum") + message(4, "Add");
    const Bytes relu = message(1, "sum") + message(2, "y") + message(4, "Relu");
    // Scalar FLOAT initializer encoded as IEEE-754 little-endian float_data.
    const Bytes bias = number(2, 1) + message(8, "bias") + varint(4 * 8 + 5) + Bytes("\0\0\0\x40", 4);
    const Bytes body = message(1, add) + message(1, relu) + message(2, "ember-add-relu") +
        message(5, bias) + message(11, value_info("x")) + message(12, value_info("y"));
    return number(1, 8) + message(2, "EmberBSD installed API contract") + message(7, body) + message(8, number(2, 13));
}

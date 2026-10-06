// SPDX-License-Identifier: MIT
#include <net.h>
#include <c_api.h>
#include <datareader.h>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
static void require(bool ok, const char *what) { if (!ok) throw std::runtime_error(what); }
int main() try {
    require(std::string(ncnn_version()) == "1.0.20260526", "unexpected ncnn version");
    ncnn::Net net;
    net.opt.use_vulkan_compute = false;
    net.opt.use_fp16_storage = false;
    net.opt.use_fp16_arithmetic = false;
    net.opt.use_bf16_storage = false;
    net.opt.num_threads = 1;
    const char model[] = "7767517\n3 3\nInput input 0 1 x\nBinaryOp add 1 1 x sum 0=0 1=1 2=2.0\nReLU relu 1 1 sum y 0=0.0\n";
    require(net.load_param_mem(model) == 0, "cannot parse ncnn graph");
    const unsigned char weights[4] = {0, 0, 0, 0};
    const unsigned char *position = weights;
    ncnn::DataReaderFromMemory reader(position);
    require(net.load_model(reader) == 0 && position == weights, "cannot initialize weightless graph");
    const float values[] = {-4, -2, -1, 0, 1, 10};
    const float expected[] = {0, 0, 1, 2, 3, 12};
    ncnn::Mat input(6);
    for (int i = 0; i < 6; ++i) input[i] = values[i];
    for (int run = 0; run < 100; ++run) {
        auto extractor = net.create_extractor();
        require(extractor.input("x", input) == 0, "input rejected");
        ncnn::Mat output;
        require(extractor.extract("y", output) == 0 && output.dims == 1 && output.w == 6 &&
                output.elempack == 1 && output.elemsize == sizeof(float), "wrong result shape");
        for (int i = 0; i < 6; ++i)
            require(std::isfinite(output[i]) && std::abs(output[i] - expected[i]) < 1e-6f, "wrong graph result");
    }
    ncnn::Net dense;
    dense.opt = net.opt;
    const char dense_graph[] = "7767517\n3 3\nInput input 0 1 x\nInnerProduct fc 1 1 x scores 0=3 1=1 2=12\nReLU relu 1 1 scores y 0=0.0\n";
    require(dense.load_param_mem(dense_graph) == 0, "cannot parse dense model");
    // A zero raw-float tag, row-major weights (3x4), then three biases.
    // This in-memory fixture is for the little-endian target profile.
    const float dense_weights[] = {0, 1, 0, 0, 0, 0, -1, 0, 0, .5f, .5f, .5f, .5f, .5f, 1, -1};
    const auto *dense_begin = reinterpret_cast<const unsigned char *>(dense_weights);
    position = dense_begin;
    ncnn::DataReaderFromMemory dense_reader(position);
    require(dense.load_model(dense_reader) == 0 && position == dense_begin + sizeof(dense_weights), "dense weight load failed");
    ncnn::Mat features(4);
    for (int i = 0; i < 4; ++i) features[i] = float(i + 1);
    auto classifier = dense.create_extractor();
    require(classifier.input("x", features) == 0, "dense input rejected");
    ncnn::Mat scores;
    require(classifier.extract("y", scores) == 0 && scores.dims == 1 && scores.w == 3 &&
            scores.elempack == 1 && scores.elemsize == sizeof(float), "dense result shape mismatch");
    const float expected_scores[] = {1.5f, 0, 4};
    for (int i = 0; i < 3; ++i)
        require(std::isfinite(scores[i]) && std::abs(scores[i] - expected_scores[i]) < 1e-6f, "wrong dense model result");
    auto invalid = net.create_extractor();
    require(invalid.input("absent", input) != 0, "unknown input name accepted");
    ncnn::Mat output;
    require(invalid.extract("absent", output) != 0, "unknown output name accepted");
    ncnn::Net bad;
    require(bad.load_param_mem("bad magic\n") != 0, "malformed graph accepted");
    std::cout << "PASS ncnn 1.0.20260526 CPU: Add/Relu, dense weights, 100 runs, malformed graph and unknown blob rejection\n";
    return 0;
} catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }

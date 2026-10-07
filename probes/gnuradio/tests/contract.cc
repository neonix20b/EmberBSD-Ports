// SPDX-License-Identifier: MIT
// Copyright (c) 2026 EmberBSD contributors
#include <gnuradio/top_block.h>
#include <gnuradio/sync_block.h>
#include <gnuradio/io_signature.h>
#include <gnuradio/constants.h>
#include <gnuradio/blocks/vector_source.h>
#include <gnuradio/blocks/vector_sink.h>
#include <gnuradio/blocks/multiply_const.h>
#include <gnuradio/channels/channel_model.h>
#include <gnuradio/digital/binary_slicer_fb.h>
#include <gnuradio/fft/fft.h>
#include <gnuradio/filter/interp_differentiator_taps.h>
#include <gnuradio/filter/mmse_interp_differentiator_ff.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdio>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

template<class Exception, class Callable>
void rejects(Callable call, const char* message) {
    try { call(); }
    catch (const Exception&) { return; }
    throw std::runtime_error(message);
}

void finite() {
    std::vector<float> input(1025);
    for (size_t i = 0; i < input.size(); ++i)
        input[i] = static_cast<float>(static_cast<int>(i % 19) - 9) / 8.0f;
    gr::tag_t marker;
    marker.offset = 257;
    marker.key = pmt::intern("frame");
    marker.value = pmt::from_long(42);
    marker.srcid = pmt::intern("ember-contract");
    auto source = gr::blocks::vector_source_f::make(input, false, 1, {marker});
    auto multiply = gr::blocks::multiply_const_ff::make(2.5f);
    auto sink = gr::blocks::vector_sink_f::make();
    auto slicer = gr::digital::binary_slicer_fb::make();
    auto bits = gr::blocks::vector_sink_b::make();
    auto graph = gr::make_top_block("ember-finite-contract");
    graph->connect(source, 0, multiply, 0);
    graph->connect(multiply, 0, sink, 0);
    graph->connect(multiply, 0, slicer, 0);
    graph->connect(slicer, 0, bits, 0);
    graph->run(127);
    const auto actual = sink->data();
    const auto decisions = bits->data();
    require(actual.size() == input.size(), "Finite scheduler lost or duplicated samples");
    require(decisions.size() == input.size(), "Binary slicer changed the sample count");
    for (size_t i = 0; i < input.size(); ++i) {
        require(actual[i] == 2.5f * input[i], "Incorrect multiply result");
        require(decisions[i] == static_cast<unsigned char>(input[i] >= 0),
                "Incorrect binary decision");
    }
    const auto tags = sink->tags();
    require(tags.size() == 1 && tags[0].offset == 257 &&
            pmt::eq(tags[0].key, marker.key) && pmt::to_long(tags[0].value) == 42,
            "Stream marker did not retain its value and absolute offset");
    // Exercise construction and parameter storage for the channel hierarchy.
    // Sample-by-sample channel behavior belongs to the independent channel example.
    auto channel = gr::channels::channel_model::make(0.125, 0.001, 1.0, {{1.0f, 0.0f}}, 42);
    // The upstream complex fast-noise source exposes its stored per-component
    // amplitude, normalized by sqrt(2), through channel_model::noise_voltage().
    const float noise_component = 0.125f / std::sqrt(2.0f);
    require(channel->noise_voltage() == static_cast<double>(noise_component) &&
            channel->frequency_offset() == 0.001 &&
            channel->timing_offset() == 1.0, "Channel parameter mismatch");
    gr::filter::mmse_interp_differentiator_ff derivative;
    require(derivative.ntaps() == DNTAPS && derivative.nsteps() == DNSTEPS,
            "Installed differentiator coefficient header does not match library");
    std::vector<float> zeros(derivative.ntaps(), 0.0f);
    for (float mu : {0.0f, 0.5f, 1.0f})
        require(derivative.differentiate(zeros.data(), mu) == 0.0f,
                "Derivative of a zero signal was nonzero");
    std::printf("finite: 1025 scaled samples, 1025 bits, stream marker and filter interface PASS\n");
}

void fft() {
    const double pi = std::acos(-1.0);
    for (int n : {31, 64}) {
        gr::fft::fft_complex_fwd forward(n, 1);
        gr::fft::fft_complex_rev inverse(n, 1);
        std::vector<gr_complex> input(n);
        for (int i = 0; i < n; ++i) {
            input[i] = gr_complex(static_cast<float>((i % 7) - 3) / 8.0f,
                                  static_cast<float>((i % 11) - 5) / 16.0f);
            forward.get_inbuf()[i] = input[i];
        }
        forward.execute();
        for (int k = 0; k < n; ++k) {
            std::complex<double> expected{};
            for (int i = 0; i < n; ++i)
                expected += std::complex<double>(input[i]) *
                    std::polar(1.0, -2.0 * pi * k * i / n);
            require(std::abs(std::complex<double>(forward.get_outbuf()[k]) - expected) < 2e-5,
                    "Installed GNU Radio FFT differs from independent DFT");
            inverse.get_inbuf()[k] = forward.get_outbuf()[k];
        }
        inverse.execute();
        for (int i = 0; i < n; ++i)
            require(std::abs(inverse.get_outbuf()[i] / static_cast<float>(n) - input[i]) < 2e-6f,
                    "FFT inverse did not reconstruct input");
        rejects<std::out_of_range>([&] { forward.set_nthreads(0); },
                                   "FFT accepted zero worker threads");
    }
    std::puts("fft: prime/composite forward DFT, inverse reconstruction and invalid threads PASS");
}

class CountingSink final : public gr::sync_block {
public:
    std::atomic<unsigned long long> samples{0};
    CountingSink() : gr::sync_block("ember-counting-sink",
        gr::io_signature::make(1, 1, sizeof(float)), gr::io_signature::make(0, 0, 0)) {}
    int work(int n, gr_vector_const_void_star&, gr_vector_void_star&) override {
        samples.fetch_add(static_cast<unsigned>(n), std::memory_order_relaxed);
        return n;
    }
};

void error_stop() {
    auto graph = gr::make_top_block("ember-error-stop-contract");
    auto source = gr::blocks::vector_source_f::make({1.0f, -1.0f, 0.25f}, true);
    auto wrong_sink = gr::blocks::vector_sink_b::make();
    rejects<std::invalid_argument>([&] { graph->connect(source, 0, wrong_sink, 0); },
                                   "Invalid stream item size was accepted");
    auto sink = gnuradio::make_block_sptr<CountingSink>();
    graph->connect(source, 0, sink, 0);
    for (int pass = 0; pass < 2; ++pass) {
        const auto before = sink->samples.load(std::memory_order_relaxed);
        graph->start(128);
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
        while (sink->samples.load(std::memory_order_relaxed) < before + 1024 &&
               std::chrono::steady_clock::now() < deadline)
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        graph->stop();
        graph->wait();
        require(sink->samples.load(std::memory_order_relaxed) >= before + 1024,
                "Scheduler did not produce samples before stop/restart");
        require(std::chrono::steady_clock::now() < deadline,
                "Scheduler stop/wait exceeded two seconds");
    }
    gr::filter::mmse_interp_differentiator_ff derivative;
    std::vector<float> zeros(derivative.ntaps(), 0.0f);
    rejects<std::runtime_error>([&] { derivative.differentiate(zeros.data(), -1.0f); },
                               "Negative interpolation phase was accepted");
    rejects<std::runtime_error>([&] { derivative.differentiate(zeros.data(), 2.0f); },
                               "Out-of-range interpolation phase was accepted");
    std::puts("error-stop: invalid connection, stop/wait/restart and invalid filter phase PASS");
}
} // namespace

int main(int argc, char** argv) {
    try {
        require(argc == 3, "Usage: gnuradio-contract finite|fft|error-stop EXPECTED_PREFIX");
        require(gr::version() == "3.10.12.0", "Unexpected GNU Radio version");
        require(std::filesystem::equivalent(gr::prefix(), argv[2]), "Runtime prefix escaped installation");
        const std::string mode = argv[1];
        if (mode == "finite") finite();
        else if (mode == "fft") fft();
        else if (mode == "error-stop") error_stop();
        else throw std::runtime_error("Unknown test mode");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 1;
    }
}

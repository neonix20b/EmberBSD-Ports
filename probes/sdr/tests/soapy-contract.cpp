// SPDX-License-Identifier: MIT
#include <SoapySDR/Device.hpp>
#include <SoapySDR/Formats.hpp>
#include <SoapySDR/Errors.hpp>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#define CHECK(x) do { if (!(x)) throw std::runtime_error("line " + std::to_string(__LINE__) + ": " #x); } while (0)
using Device = std::unique_ptr<SoapySDR::Device, void(*)(SoapySDR::Device*)>;
static SoapySDR::Kwargs args(const char *uri) { return {{"driver", "plutosdr"}, {"uri", uri}}; }
static void receive(SoapySDR::Device &dev, const char *format)
{
    auto *stream = dev.setupStream(SOAPY_SDR_RX, format, {0}, {{"bufflen", "64"}});
    CHECK(stream);
    CHECK(dev.activateStream(stream) == 0);
    size_t offset = 0;
    for (size_t count : {size_t(17), size_t(47), size_t(29), size_t(35)}) {
        int16_t raw[128]{};
        float scaled[128]{};
        void *buffers[] = {std::string(format) == SOAPY_SDR_CS16 ? static_cast<void*>(raw) : scaled};
        int flags = 0; long long stamp = 0;
        CHECK(dev.readStream(stream, buffers, count, flags, stamp, 250000) == int(count));
        for (size_t n = 0; n < count; ++n) {
            const int i = int((offset + n) % 31) - 15;
            const int q = 100 - int((offset + n) % 17);
            if (std::string(format) == SOAPY_SDR_CS16) {
                CHECK(raw[2*n] == i && raw[2*n+1] == q);
            } else {
                CHECK(std::fabs(scaled[2*n] - i / 2048.0f) < 1e-7f);
                CHECK(std::fabs(scaled[2*n+1] - q / 2048.0f) < 1e-7f);
            }
        }
        offset += count;
    }
    CHECK(dev.deactivateStream(stream) == 0);
    dev.closeStream(stream);
}
int main(int argc, char **argv)
try {
    CHECK(argc == 5);
    auto first = SoapySDR::Device::enumerate(args(argv[1]));
    CHECK(first.size() == 1 && first[0].at("uri") == argv[1]);
    CHECK(SoapySDR::Device::enumerate(args("emu:/no-such-emberbsd-sdr-fixture.xml")).empty());
    CHECK(SoapySDR::Device::enumerate(args(argv[3])).empty());
    CHECK(SoapySDR::Device::enumerate(args(argv[4])).empty());
    auto second = SoapySDR::Device::enumerate(args(argv[2]));
    CHECK(second.size() == 1 && second[0].at("uri") == argv[2]);
    Device a(SoapySDR::Device::make(args(argv[1])), SoapySDR::Device::unmake);
    Device b(SoapySDR::Device::make(args(argv[2])), SoapySDR::Device::unmake);
    CHECK(a && b);
    CHECK(a->getHardwareInfo().at("fixture_id") == "fixture-one");
    CHECK(b->getHardwareInfo().at("fixture_id") == "fixture-two");
    a->setFrequency(SOAPY_SDR_RX, 0, "RF", 916000000);
    CHECK(a->getFrequency(SOAPY_SDR_RX, 0, "RF") == 916000000);
    CHECK(b->getFrequency(SOAPY_SDR_RX, 0, "RF") == 915000000);
    bool rejected = false;
    try { a->setupStream(SOAPY_SDR_RX, "INVALID", {0}); } catch (const std::exception &) { rejected = true; }
    CHECK(rejected);
    receive(*a, SOAPY_SDR_CS16);
    receive(*b, SOAPY_SDR_CF32);
    a.reset();
    CHECK(b->getHardwareInfo().at("fixture_id") == "fixture-two");
    std::cout << "PASS Soapy: explicit URI, no stale discovery, isolated contexts, attributes, invalid format, CS16/CF32 RX tails\n";
    return 0;
} catch (const std::exception &e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }

// SPDX-License-Identifier: MIT
#include <SoapySDR/Device.hpp>
#include <SoapySDR/Formats.hpp>
#include <SoapySDR/Errors.hpp>
#include <cstdint>
#include <iostream>
int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    auto *device = SoapySDR::Device::make(SoapySDR::Kwargs{{"driver", "plutosdr"}, {"uri", argv[1]}});
    if (!device) return 1;
    auto *stream = device->setupStream(SOAPY_SDR_RX, SOAPY_SDR_CS16, {0}, {{"bufflen", "64"}});
    device->activateStream(stream);
    int16_t samples[128]; void *buffers[] = {samples};
    int flags = 0; long long time = 0;
    int result = device->readStream(stream, buffers, 64, flags, time, 250000);
    device->deactivateStream(stream);
    device->closeStream(stream);
    SoapySDR::Device::unmake(device);
    std::cout << "empty IQ source result=" << result << ", expected=" << SOAPY_SDR_STREAM_ERROR << '\n';
    if (result != SOAPY_SDR_STREAM_ERROR) return 1;
    std::cout << "PASS failed RX source is a stream error, not a timeout\n";
    return 0;
}

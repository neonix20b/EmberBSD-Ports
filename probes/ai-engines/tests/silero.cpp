// SPDX-License-Identifier: MIT
#include <onnxruntime_cxx_api.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

static void require(bool ok, const char *what) { if (!ok) throw std::runtime_error(what); }
static uint32_t little(const unsigned char *p, size_t n) {
    uint32_t result = 0;
    for (size_t i = 0; i < n; ++i) result |= uint32_t(p[i]) << (i * 8);
    return result;
}
static std::vector<float> read_wave(const char *path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    require(file.good(), "cannot open WAV");
    const auto length = file.tellg();
    require(length >= 12 && length <= 128 * 1024 * 1024, "invalid WAV size");
    file.seekg(0);
    std::vector<unsigned char> bytes(static_cast<size_t>(length));
    file.read(reinterpret_cast<char *>(bytes.data()), length);
    require(file.good(), "short WAV read");
    require(std::memcmp(bytes.data(), "RIFF", 4) == 0 && std::memcmp(bytes.data() + 8, "WAVE", 4) == 0, "invalid WAV signature");
    require(size_t(little(bytes.data() + 4, 4)) + 8 == bytes.size(), "truncated WAV container");
    bool format = false, audio = false;
    std::vector<float> samples;
    for (size_t pos = 12; pos < bytes.size();) {
        require(bytes.size() - pos >= 8, "truncated WAV chunk header");
        const size_t count = little(bytes.data() + pos + 4, 4);
        require(count <= bytes.size() - pos - 8, "truncated WAV chunk");
        const auto *data = bytes.data() + pos + 8;
        if (std::memcmp(bytes.data() + pos, "fmt ", 4) == 0) {
            require(!format && count >= 16, "invalid WAV format");
            require(little(data, 2) == 1 && little(data + 2, 2) == 1 && little(data + 4, 4) == 16000 &&
                    little(data + 8, 4) == 32000 && little(data + 12, 2) == 2 && little(data + 14, 2) == 16,
                    "WAV must be mono 16 kHz PCM16");
            format = true;
        } else if (std::memcmp(bytes.data() + pos, "data", 4) == 0) {
            require(format && !audio && count > 0 && count % 2 == 0, "invalid WAV audio");
            samples.reserve(count / 2);
            for (size_t i = 0; i < count; i += 2) {
                const int value = static_cast<int>(little(data + i, 2));
                samples.push_back(static_cast<float>(value >= 32768 ? value - 65536 : value) / 32768.0f);
            }
            audio = true;
        }
        pos += 8 + count;
        if (count & 1) { require(pos < bytes.size(), "missing WAV chunk padding"); ++pos; }
    }
    require(audio, "WAV has no samples");
    return samples;
}

class Stream {
    Ort::Session session;
    Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::array<float, 256> state{};
    std::array<float, 64> context{};
    std::array<float, 512> pending{};
    size_t used = 0;
    bool finished = false;
    void frame() {
        std::array<float, 576> data;
        std::copy(context.begin(), context.end(), data.begin());
        std::copy(pending.begin(), pending.end(), data.begin() + 64);
        std::array<int64_t, 2> input_shape{1, 576};
        std::array<int64_t, 3> state_shape{2, 1, 128};
        int64_t rate = 16000;
        std::array<Ort::Value, 3> inputs{
            Ort::Value::CreateTensor<float>(memory, data.data(), data.size(), input_shape.data(), input_shape.size()),
            Ort::Value::CreateTensor<float>(memory, state.data(), state.size(), state_shape.data(), state_shape.size()),
            Ort::Value::CreateTensor<int64_t>(memory, &rate, 1, nullptr, 0)
        };
        const char *names[] = {"input", "state", "sr"};
        const char *output_names[] = {"output", "stateN"};
        auto output = session.Run(Ort::RunOptions{nullptr}, names, inputs.data(), inputs.size(), output_names, 2);
        require(output.size() == 2 && output[0].GetTensorTypeAndShapeInfo().GetElementCount() == 1 &&
                output[1].GetTensorTypeAndShapeInfo().GetShape() == std::vector<int64_t>({2, 1, 128}), "invalid VAD outputs");
        const float probability = output[0].GetTensorData<float>()[0];
        require(std::isfinite(probability) && probability >= 0 && probability <= 1, "invalid speech probability");
        const auto *next = output[1].GetTensorData<float>();
        for (size_t i = 0; i < state.size(); ++i) { require(std::isfinite(next[i]), "invalid recurrent state"); state[i] = next[i]; }
        probabilities.push_back(probability);
        std::copy(data.end() - 64, data.end(), context.begin());
        used = 0;
    }
public:
    std::vector<float> probabilities;
    size_t samples = 0;
    Stream(Ort::Env &env, const char *model, const Ort::SessionOptions &options) : session(env, model, options) {}
    void append(const float *data, size_t count, int rate = 16000) {
        require(!finished && rate == 16000 && (data || count == 0), "invalid VAD stream input");
        for (size_t i = 0; i < count; ++i) require(std::isfinite(data[i]) && std::abs(data[i]) <= 1, "invalid PCM sample");
        samples += count;
        for (size_t i = 0; i < count; ++i) {
            pending[used++] = data[i];
            if (used == pending.size()) frame();
        }
    }
    void finish() {
        require(!finished, "VAD stream already closed");
        if (used) { std::fill(pending.begin() + used, pending.end(), 0); frame(); }
        finished = true;
    }
};

int main(int argc, char **argv) try {
    require(argc == 3, "usage: silero-contract MODEL.onnx INPUT.wav");
    auto speech = read_wave(argv[2]);
    std::vector<float> audio(16000, 0);
    audio.insert(audio.end(), speech.begin(), speech.end());
    audio.insert(audio.end(), 32000, 0);
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "ember-silero");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1).SetInterOpNumThreads(1);
    Stream whole(env, argv[1], options), chunked(env, argv[1], options);
    whole.append(audio.data(), audio.size()); whole.finish();
    const size_t chunks[] = {1, 117, 777, 4096, 31};
    for (size_t pos = 0, turn = 0; pos < audio.size(); ++turn) {
        size_t count = std::min(chunks[turn % 5], audio.size() - pos);
        chunked.append(audio.data() + pos, count); pos += count;
    }
    chunked.finish();
    require(whole.samples == audio.size() && chunked.samples == audio.size(), "lost audio samples");
    require(whole.probabilities.size() == (audio.size() + 511) / 512 &&
            chunked.probabilities.size() == whole.probabilities.size(), "wrong frame count");
    size_t detected = 0, first = whole.probabilities.size(), last = 0;
    for (size_t i = 0; i < whole.probabilities.size(); ++i) {
        require(std::abs(whole.probabilities[i] - chunked.probabilities[i]) <= 1e-6f, "stream boundary changed inference");
        if (whole.probabilities[i] >= 0.5f) { ++detected; first = std::min(first, i); last = i; }
    }
    require(detected >= 10, "fixture did not produce speech");
    require(first >= 20 && last + 20 < whole.probabilities.size(), "speech leaked into injected silence");
    for (size_t i = 0; i < 20; ++i) {
        require(whole.probabilities[i] < 0.5f, "leading silence detected as speech");
        require(whole.probabilities[whole.probabilities.size() - 1 - i] < 0.5f, "trailing silence detected as speech");
    }
    Stream invalid(env, argv[1], options);
    bool rejected = false;
    try { invalid.append(audio.data(), 512, 44100); } catch (const std::runtime_error &) { rejected = true; }
    require(rejected, "unsupported sample rate accepted");
    rejected = false;
    float bad = NAN;
    try { invalid.append(&bad, 1); } catch (const std::runtime_error &) { rejected = true; }
    require(rejected && invalid.samples == 0 && invalid.probabilities.empty(), "invalid samples changed state");
    std::cout << "PASS Silero 6.2.3 CPU: samples=" << whole.samples << " frames=" << whole.probabilities.size()
              << " speech_frames=" << detected << " first=" << first * .032 << " last=" << (last + 1) * .032
              << "s; arbitrary chunks, silence boundaries and invalid PCM/rate rejection\n";
    return 0;
} catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }

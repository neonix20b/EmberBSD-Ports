// SPDX-License-Identifier: MIT
#include <onnxruntime_cxx_api.h>
#include <pthread.h>
#include <sched.h>
#include <unistd.h>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <iostream>
#include <memory>
#include <new>
#include <stdexcept>
#include <thread>
#include "onnx-graph.h"
#include "netbsd-affinity.h"

static void require(bool ok, const char *what)
{
    if (!ok) throw std::runtime_error(what);
}

struct Worker {
    pthread_t thread{};
    OrtThreadWorkerFn function;
    void *argument;
};

static void *start_worker(void *argument)
{
    auto *worker = static_cast<Worker *>(argument);
    worker->function(worker->argument);
    return nullptr;
}

static OrtCustomThreadHandle create_worker(void *context, OrtThreadWorkerFn function, void *argument)
{
    auto **slot = static_cast<Worker **>(context);
    if (*slot != nullptr) return nullptr;
    auto worker = std::unique_ptr<Worker>(new (std::nothrow) Worker{{}, function, argument});
    if (!worker || pthread_create(&worker->thread, nullptr, start_worker, worker.get()) != 0)
        return nullptr;
    *slot = worker.release();
    return reinterpret_cast<OrtCustomThreadHandle>(*slot);
}

static void join_worker(OrtCustomThreadHandle handle)
{
    auto *worker = reinterpret_cast<Worker *>(const_cast<OrtCustomHandleType *>(handle));
    if (pthread_join(worker->thread, nullptr) != 0) std::terminate();
    delete worker;
}

static void ORT_API_CALL logger(void *context, OrtLoggingLevel level, const char *,
    const char *, const char *, const char *text)
{
    if (level >= ORT_LOGGING_LEVEL_ERROR) {
        static_cast<std::atomic<unsigned> *>(context)->fetch_add(1);
        std::cerr << text << '\n';
    }
}

int main() try
{
    const long count = sysconf(_SC_NPROCESSORS_CONF);
    const auto available = two_available_cpus(count);
    std::atomic<unsigned> errors{0};
    Ort::Env env(ORT_LOGGING_LEVEL_VERBOSE, "ember-affinity", logger, &errors);
    for (cpuid_t selected : available) {
        Worker *worker = nullptr;
        Ort::SessionOptions options;
        options.SetIntraOpNumThreads(2).SetInterOpNumThreads(1);
        options.AddConfigEntry("session.intra_op_thread_affinities", std::to_string(selected + 1).c_str());
        // The supplied worker function still enters ORT's PosixThread::ThreadMain,
        // where the NetBSD patch applies the affinity. This wrapper only retains
        // the pthread handle so the test can query the actual kernel mask.
        options.SetCustomCreateThreadFn(create_worker).SetCustomThreadCreationOptions(&worker);
        options.SetCustomJoinThreadFn(join_worker);
        const auto model = graph();
        Ort::Session session(env, model.data(), model.size(), options);
        require(worker != nullptr, "ORT did not create its worker");
        CpuSet mask(cpuset_create());
        require(mask != nullptr, "cpuset allocation failed");
        bool pinned = false;
        for (int attempt = 0; attempt < 100 && !pinned; ++attempt) {
            cpuset_zero(mask.get());
            require(pthread_getaffinity_np(worker->thread, cpuset_size(mask.get()), mask.get()) == 0,
                "cannot read worker affinity");
            pinned = true;
            for (long cpu = 0; cpu < count; ++cpu)
                pinned = pinned && cpuset_isset(cpu, mask.get()) == (static_cast<cpuid_t>(cpu) == selected ? 1 : 0);
            if (!pinned) std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        require(pinned, "ORT worker affinity did not match requested CPU");
        auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        std::array<float, 6> input{-4, -2, -1, 0, 1, 10};
        const std::array<float, 6> expected{0, 0, 1, 2, 3, 12};
        const std::array<int64_t, 1> shape{6};
        auto tensor = Ort::Value::CreateTensor<float>(memory, input.data(), input.size(), shape.data(), 1);
        const char *inputs[] = {"x"}, *outputs[] = {"y"};
        auto result = session.Run(Ort::RunOptions{nullptr}, inputs, &tensor, 1, outputs, 1);
        require(result.size() == 1 && result[0].GetTensorTypeAndShapeInfo().GetElementCount() == 6,
            "wrong affinity-session output shape");
        const float *values = result[0].GetTensorData<float>();
        for (size_t i = 0; i < expected.size(); ++i)
            require(std::isfinite(values[i]) && std::abs(values[i] - expected[i]) < 1e-6f,
                "wrong affinity-session inference result");
        require(errors.load() == 0, "ORT logged an affinity/runtime error");
    }
    std::cout << "PASS ONNX Runtime affinity: two intra-op threads, worker masks CPU "
        << available[0] << " then CPU " << available[1] << ", exact graph results\n";
    return 0;
} catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }

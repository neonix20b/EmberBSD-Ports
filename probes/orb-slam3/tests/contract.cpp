// SPDX-License-Identifier: MIT
#include <System.h>
#include <ORBextractor.h>
#include <ThreadUtils.h>
#include <TrackingHistory.h>
#include <OptimizerStop.h>
#include <Thirdparty/g2o/g2o/core/optimization_algorithm.h>
#include <Thirdparty/g2o/g2o/types/types_six_dof_expmap.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <thread>
#ifdef __NetBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#endif

static void require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static int threads()
{
#ifdef __NetBSD__
    kinfo_proc2 process{};
    int mib[] = {CTL_KERN, KERN_PROC2, KERN_PROC_PID, getpid(), sizeof(process), 1};
    size_t size = sizeof(process);
    require(sysctl(mib, 6, &process, &size, nullptr, 0) == 0 && size == sizeof(process),
        "cannot obtain native thread count");
    return static_cast<int>(process.p_nlwps);
#else
    return -1;
#endif
}

class JoinProbe : public ORB_SLAM3::LoopClosing {
public:
    JoinProbe() : LoopClosing(nullptr, nullptr, nullptr, true, true) {}
    void start(std::atomic<bool> &finished)
    {
        require(mpThreadGBA == nullptr, "previous GBA thread ownership was not released");
        mbRunningGBA = true;
        mbFinishedGBA = false;
        mpThreadGBA = new std::thread([this, &finished] {
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
            // The real GBA worker takes this mutex before it can finish.
            // Joining while holding it must fail the test timeout.
            std::unique_lock<std::mutex> lock(mMutexGBA);
            mbRunningGBA = false;
            mbFinishedGBA = true;
            finished = true;
        });
    }
    bool released() const { return mpThreadGBA == nullptr; }
    void stop_mapping() { StopLocalMappingForLoop(); }
    void start_releasing_mapping()
    {
        mbRunningGBA = true;
        mbFinishedGBA = false;
        mbStopGBA = false;
        mpThreadGBA = new std::thread([this] {
            // Release only after the production cancellation handshake. With
            // the old ordering its earlier RequestStop is deterministically
            // erased; with the fixed ordering RequestStop follows this tail.
            while (!mbStopGBA.load()) std::this_thread::yield();
            std::unique_lock<std::mutex> lock(mMutexGBA);
            mpLocalMapper->Release();
            mbRunningGBA = false;
            mbFinishedGBA = true;
        });
    }
    bool generations()
    {
        mnFullBAIdx = 0;
        ++mnFullBAIdx;
        ++mnFullBAIdx;
        ++mnFullBAIdx;
        return mnFullBAIdx == 3;
    }
};

class MappingProbe : public ORB_SLAM3::LocalMapping {
public:
    MappingProbe() : LocalMapping(nullptr, nullptr, false, false, "") { mbFinished = false; }
};

// Controlled scheduling inside the real SparseOptimizer::optimize loop.
// This tests termination plumbing, not numerical bundle adjustment.
class IterationGate : public g2o::OptimizationAlgorithm {
public:
    std::atomic<bool> entered{false}, resume{false};
    bool init(bool) override { return true; }
    SolverResult solve(int, bool) override
    {
        entered = true;
        while (!resume) std::this_thread::yield();
        return OK;
    }
    bool computeMarginals(g2o::SparseBlockMatrix<Eigen::MatrixXd> &,
        const std::vector<std::pair<int, int>> &) override { return false; }
    bool updateStructure(const std::vector<g2o::HyperGraph::Vertex*> &,
        const g2o::HyperGraph::EdgeSet &) override { return false; }
};

static void atomic_stop()
{
    g2o::SparseOptimizer optimizer;
    auto *point = new g2o::VertexSBAPointXYZ;
    point->setId(0);
    point->setEstimate(Eigen::Vector3d(0, 0, 1));
    require(optimizer.addVertex(point), "cannot add termination fixture vertex");
    auto *camera = new g2o::VertexSE3Expmap;
    camera->setId(1);
    camera->setFixed(true);
    require(optimizer.addVertex(camera), "cannot add termination fixture camera");
    auto *edge = new g2o::EdgeSE3ProjectXYZ;
    edge->setVertex(0, point);
    edge->setVertex(1, camera);
    edge->setMeasurement(Eigen::Vector2d::Zero());
    edge->setInformation(Eigen::Matrix2d::Identity());
    edge->fx = edge->fy = 1;
    edge->cx = edge->cy = 0;
    require(optimizer.addEdge(edge), "cannot add termination fixture edge");
    auto *gate = new IterationGate;
    optimizer.setAlgorithm(gate);
    require(optimizer.initializeOptimization(), "cannot initialize termination fixture");
    std::atomic<bool> stop(false);
    ORB_SLAM3::SetOptimizerStop(optimizer, &stop);
    int iterations = -1;
    std::thread worker([&] { iterations = optimizer.optimize(100); });
    while (!gate->entered) std::this_thread::yield();
    stop.store(true, std::memory_order_relaxed);
    gate->resume = true;
    worker.join();
    require(iterations == 1, "real g2o optimizer did not stop after atomic cancellation");
    bool plain = false;
    ORB_SLAM3::SetOptimizerStop(optimizer, &plain);
    require(!optimizer.terminate(), "legacy stop setter retained atomic flag");
    plain = true;
    require(optimizer.terminate(), "legacy bool stop API stopped working");
    optimizer.setAtomicForceStopFlag(nullptr);
    require(!optimizer.terminate(), "clearing atomic flag retained legacy flag");
}

static void features()
{
    cv::Mat image(480, 640, CV_8UC1);
    cv::RNG random(123456);
    random.fill(image, cv::RNG::UNIFORM, 0, 256);
    ORB_SLAM3::ORBextractor extractor(1000, 1.2f, 8, 20, 7);
    std::vector<cv::KeyPoint> keypoints;
    std::vector<int> overlap{0, 0};
    cv::Mat descriptors;
    extractor(image, cv::noArray(), keypoints, descriptors, overlap);
    require(keypoints.size() > 700, "synthetic texture did not produce enough ORB features");
    require(descriptors.rows == static_cast<int>(keypoints.size()) &&
        descriptors.cols == 32 && descriptors.type() == CV_8UC1,
        "ORB descriptor shape/type mismatch");
    for (const auto &point : keypoints)
        require(std::isfinite(point.pt.x) && std::isfinite(point.pt.y) &&
            point.pt.x >= 0 && point.pt.x < image.cols &&
            point.pt.y >= 0 && point.pt.y < image.rows, "invalid keypoint");
    Eigen::Vector3f translation(1, 2, 3), input(4, -2, 1);
    Sophus::SE3f pose(Eigen::Matrix3f::Identity(), translation);
    require((pose.inverse() * (pose * input) - input).norm() < 1e-5f,
        "installed Sophus/Eigen transform round trip failed");
    std::cout << "features=" << keypoints.size() << " OpenCV=" << CV_VERSION << '\n';
}

int main(int argc, char **argv)
{
    try {
        require(argc == 4, "usage: orb-contract CASE VOCABULARY SETTINGS");
        cv::setNumThreads(1);
        std::string mode(argv[1]);
        if (mode == "features") {
            features();
        } else if (mode == "viewer") {
            bool rejected = false;
            try {
                ORB_SLAM3::System system("missing-vocabulary", "missing-settings",
                    ORB_SLAM3::System::RGBD, true);
            } catch (const std::invalid_argument &error) {
                rejected = std::string(error.what()).find("headless") != std::string::npos;
            }
            require(rejected, "headless build must reject viewer=true before input loading");
        } else if (mode == "gba-join") {
            JoinProbe probe;
            require(probe.generations(), "GBA generation counter must not saturate at one");
            for (int generation = 0; generation != 3; ++generation) {
                std::atomic<bool> finished(false);
                probe.start(finished);
                probe.JoinGlobalBundleAdjustment();
                require(finished && probe.released() && !probe.isRunningGBA() && probe.isFinishedGBA(),
                    "GBA join returned before worker completion or retained thread ownership");
                probe.JoinGlobalBundleAdjustment();
            }
        } else if (mode == "gba-stop-order") {
            MappingProbe mapping;
            JoinProbe probe;
            probe.SetLocalMapper(&mapping);
            probe.start_releasing_mapping();
            probe.stop_mapping();
            require(mapping.stopRequested() && mapping.Stop() && mapping.isStopped(),
                "finishing GBA erased the loop correction stop request");
        } else if (mode == "atomic-stop") {
            atomic_stop();
        } else if (mode == "self-join") {
            std::atomic<bool> ready(false), returned(false);
            std::thread worker;
            worker = std::thread([&] {
                while (!ready) std::this_thread::yield();
                ORB_SLAM3::JoinUnlessCurrent(worker);
                returned = true;
            });
            ready = true;
            while (!returned) std::this_thread::yield();
            ORB_SLAM3::JoinUnlessCurrent(worker);
            ORB_SLAM3::JoinUnlessCurrent(worker);
            require(returned && !worker.joinable(), "worker self-join was not avoided");
        } else if (mode == "unavailable-pose") {
            std::list<Sophus::SE3f> poses{Sophus::SE3f{}};
            std::list<ORB_SLAM3::KeyFrame *> references{nullptr};
            std::list<double> timestamps{1.0};
            std::list<bool> lost{false};
            for (double timestamp : {2.0, 3.0}) {
                // This is the actual helper used by Tracking's missing-pose
                // branch, which previously copied time and claimed not lost.
                ORB_SLAM3::AppendUnavailableFrame(poses, references, timestamps, lost, timestamp);
                require(timestamps.back() == timestamp && lost.back(),
                    "unavailable pose repeated an old timestamp or claimed tracking success");
            }
            require(poses.size() == 3 && references.size() == 3 &&
                timestamps.size() == 3 && lost.size() == 3 && !lost.front(),
                "tracking history lists lost alignment");
        } else if (mode == "shutdown") {
            const int before = threads();
            ORB_SLAM3::System system(argv[2], argv[3], ORB_SLAM3::System::RGBD, false);
            const int during = threads();
            system.Shutdown();
            const int after = threads();
            std::cout << "threads before=" << before << " during=" << during
                << " after=" << after << '\n';
            require(system.isShutDown(), "shutdown flag not set");
            if (before >= 0) {
                require(during >= before + 2, "mapping and loop-closing threads were not created");
                require(after == before, "Shutdown returned with native worker threads alive");
            }
            system.Shutdown();
        } else {
            throw std::runtime_error("unknown case");
        }
        std::cout << "PASS " << argv[1] << '\n';
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}

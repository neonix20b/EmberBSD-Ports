// SPDX-License-Identifier: MIT
#include <behaviortree_cpp/bt_factory.h>
#include <behaviortree_cpp/loggers/bt_file_logger_v2.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

using namespace std::chrono_literals;
using Status = BT::NodeStatus;
using Clock = std::chrono::steady_clock;

static void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

struct Counters {
    std::atomic<int> started{0}, finished{0}, halted{0}, active{0};
};

// An asynchronous request/reply action. The worker has an interruptible wait;
// every completion, halt and destructor joins it before releasing the state.
class Request : public BT::StatefulActionNode {
public:
    Request(const std::string& name, const BT::NodeConfig& config, Counters& counts)
        : BT::StatefulActionNode(name, config), counts_(counts) {}
    ~Request() override { stop(); }
    static BT::PortsList providedPorts()
    {
        return {BT::InputPort<int>("delay_ms"), BT::InputPort<bool>("succeed"),
            BT::OutputPort<int>("answer")};
    }
    Status onStart() override
    {
        const auto delay = getInput<int>("delay_ms");
        const auto outcome = getInput<bool>("succeed");
        if (!delay || !outcome || delay.value() < 1 || delay.value() > 1000)
            throw BT::RuntimeError("invalid request inputs");
        succeed_ = outcome.value();
        stop();
        cancelled_ = false;
        ready_ = false;
        ++counts_.started;
        worker_ = std::thread([this, duration = delay.value()] {
            ++counts_.active;
            std::unique_lock<std::mutex> lock(mutex_);
            if (!cv_.wait_for(lock, std::chrono::milliseconds(duration),
                    [this] { return cancelled_; })) ready_ = true;
            --counts_.active;
        });
        return Status::RUNNING;
    }
    Status onRunning() override
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (!ready_) return Status::RUNNING;
        }
        worker_.join();
        ++counts_.finished;
        if (succeed_) setOutput("answer", 42);
        return succeed_ ? Status::SUCCESS : Status::FAILURE;
    }
    void onHalted() override
    {
        stop();
        ++counts_.halted;
    }
private:
    void stop()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            cancelled_ = true;
        }
        cv_.notify_all();
        if (worker_.joinable()) worker_.join();
    }
    Counters& counts_;
    std::thread worker_;
    std::mutex mutex_;
    std::condition_variable cv_;
    bool cancelled_ = false, ready_ = false, succeed_ = false;
};

static std::string xml(const std::string& nodes)
{
    return "<root BTCPP_format=\"4\" main_tree_to_execute=\"Main\">"
        "<BehaviorTree ID=\"Main\">" + nodes + "</BehaviorTree></root>";
}

static void register_request(BT::BehaviorTreeFactory& factory, Counters& counts)
{
    factory.registerBuilder<Request>("Request",
        [&counts](const std::string& name, const BT::NodeConfig& config) {
            return std::make_unique<Request>(name, config, counts);
        });
}

static Status finish(BT::Tree& tree)
{
    const auto limit = Clock::now() + 2s;
    while (Clock::now() < limit) {
        const auto status = tree.tickOnce();
        if (status != Status::RUNNING) return status;
        std::this_thread::sleep_for(1ms);
    }
    tree.haltTree();
    throw std::runtime_error("tree did not finish within two seconds");
}

static void reset(BT::Tree& tree)
{
    tree.haltTree();
    for (const auto& subtree : tree.subtrees)
        for (const auto& node : subtree->nodes)
            require(node->status() == Status::IDLE, "haltTree did not reset every node");
}

static void success_or_failure(bool succeed)
{
    Counters counts;
    BT::BehaviorTreeFactory factory;
    register_request(factory, counts);
    const std::string action = std::string("<Request delay_ms=\"30\" succeed=\"") +
        (succeed ? "true" : "false") + "\" answer=\"{answer}\"/>";
    auto tree = factory.createTreeFromText(xml("<Sequence>" + action +
        "<Script code=\"after:=1\"/></Sequence>"));
    tree.rootBlackboard()->set("answer", -1);
    tree.rootBlackboard()->set("after", 0);
    require(tree.tickOnce() == Status::RUNNING, "request did not start asynchronously");
    require(counts.finished == 0, "worker completed in the initial tick");
    require(finish(tree) == (succeed ? Status::SUCCESS : Status::FAILURE), "wrong tree result");
    require(counts.finished == 1 && counts.active == 0 && counts.halted == 0,
        "wrong worker lifecycle after completion");
    require(tree.rootBlackboard()->get<int>("answer") == (succeed ? 42 : -1), "wrong output");
    require(tree.rootBlackboard()->get<int>("after") == (succeed ? 1 : 0), "sequence did not short-circuit");
    reset(tree);
    require(finish(tree) == (succeed ? Status::SUCCESS : Status::FAILURE), "restart failed");
    require(counts.started == 2 && counts.finished == 2 && counts.active == 0, "restart reused old work");
    reset(tree);
}

static void cancellation(bool timeout)
{
    Counters counts;
    BT::BehaviorTreeFactory factory;
    register_request(factory, counts);
    std::string action = "<Request delay_ms=\"1000\" succeed=\"true\" answer=\"{answer}\"/>";
    if (timeout) action = "<Timeout msec=\"30\">" + action + "</Timeout>";
    auto tree = factory.createTreeFromText(xml(action));
    tree.rootBlackboard()->set("answer", -1);
    require(tree.tickOnce() == Status::RUNNING, "request did not run before cancellation");
    const auto start = Clock::now();
    if (timeout) require(finish(tree) == Status::FAILURE, "timeout did not return failure");
    else tree.haltTree();
    require(Clock::now() - start < 900ms, "cancel waited for the original request");
    require(counts.halted == 1 && counts.finished == 0 && counts.active == 0, "worker leaked after cancel");
    require(tree.rootBlackboard()->get<int>("answer") == -1, "cancelled request published an answer");
    reset(tree);
    require(tree.tickOnce() == Status::RUNNING && counts.started == 2, "cancelled tree could not restart");
    reset(tree);
    require(counts.halted == 2 && counts.active == 0 && counts.finished == 0, "restart cancellation failed");
}

static void malformed()
{
    Counters counts;
    BT::BehaviorTreeFactory factory;
    register_request(factory, counts);
    const std::vector<std::string> inputs = {
        "<root><BehaviorTree>", xml("<UnknownAction/>"),
        xml("<Sequence/>"), xml("<Request delay_ms=\"bad\" succeed=\"true\"/>"),
        xml("<Request delay_ms=\"30\" succeed=\"{missing}\"/>")
    };
    for (const auto& input : inputs) {
        bool rejected = false;
        try { auto tree = factory.createTreeFromText(input); (void)tree.tickOnce(); }
        catch (const std::exception& error) { rejected = std::string(error.what()).size() > 0; }
        require(rejected, "malformed tree or invalid input was accepted");
    }
    require(counts.active == 0 && counts.started == 0, "invalid input started a worker");
}

static std::uint64_t little(const std::vector<unsigned char>& data, size_t at, size_t count)
{
    require(at <= data.size() && count <= data.size() - at, "truncated transition log");
    std::uint64_t result = 0;
    for (size_t i = 0; i < count; ++i) result |= std::uint64_t(data[at + i]) << (8 * i);
    return result;
}

static bool logged_success(const std::filesystem::path& path, uint16_t uid)
{
    std::ifstream file(path, std::ios::binary);
    const std::vector<unsigned char> data((std::istreambuf_iterator<char>(file)), {});
    const std::string magic = "BTCPP4-FileLogger2";
    if (data.size() < magic.size() + 5) return false;
    require(std::string(data.begin(), data.begin() + magic.size()) == magic, "wrong log signature");
    require(data[magic.size()] == 1, "unexpected log protocol");
    const size_t xml_size = little(data, magic.size() + 1, 4);
    require(xml_size > 0 && xml_size < 65536, "invalid XML length in transition log");
    const size_t xml_start = magic.size() + 5;
    const size_t records = xml_start + xml_size + 8;
    if (data.size() < records) return false;
    require(std::string(data.begin() + xml_start, data.begin() + xml_start + xml_size)
        .find("Request") != std::string::npos, "tree missing from transition log");
    require(little(data, records - 8, 8) > 0, "missing initial log timestamp");
    if ((data.size() - records) % 9 != 0) return false;
    bool running = false, success = false;
    std::uint64_t previous = 0;
    for (size_t at = records; at < data.size(); at += 9) {
        const auto timestamp = little(data, at, 6);
        require(timestamp >= previous, "log timestamps moved backwards");
        previous = timestamp;
        const auto node = little(data, at + 6, 2);
        const auto status = little(data, at + 8, 1);
        require(status <= static_cast<unsigned>(Status::SKIPPED), "invalid logged status");
        if (node != uid) continue;
        if (status == static_cast<unsigned>(Status::RUNNING)) running = true;
        if (status == static_cast<unsigned>(Status::SUCCESS)) {
            require(running, "success logged without running");
            success = true;
        }
    }
    return success;
}

static void logging()
{
    const auto path = std::filesystem::current_path() / "contract.btlog";
    require(!std::filesystem::exists(path), "refusing to overwrite an existing test log");
    struct Remove { std::filesystem::path path; ~Remove() { std::error_code ec; std::filesystem::remove(path, ec); } } remove{path};
    Counters counts;
    BT::BehaviorTreeFactory factory;
    register_request(factory, counts);
    auto tree = factory.createTreeFromText(xml("<Request delay_ms=\"30\" succeed=\"true\"/>"));
    const auto uid = tree.rootNode()->UID();
    {
        BT::FileLogger2 logger(tree, path);
        require(tree.tickOnce() == Status::RUNNING, "logged action did not run");
        require(finish(tree) == Status::SUCCESS, "logged action failed");
        // FileLogger2::flush is not a queue barrier. Wait for its writer thread
        // to serialize the required transitions before destroying the logger.
        const auto limit = Clock::now() + 2s;
        while (!logged_success(path, uid) && Clock::now() < limit) std::this_thread::sleep_for(2ms);
        require(logged_success(path, uid), "transition writer did not finish in time");
    }
    require(logged_success(path, uid), "closed transition log is incomplete");
    require(counts.active == 0, "logging left a worker active");
    reset(tree);
}

int main(int argc, char** argv)
{
    try {
        require(std::string(BTCPP_LIBRARY_VERSION) == "4.9.0", "wrong BehaviorTree headers");
        require(argc == 2, "one test case is required");
        const std::string test = argv[1];
        if (test == "success") success_or_failure(true);
        else if (test == "failure") success_or_failure(false);
        else if (test == "cancel") cancellation(false);
        else if (test == "timeout") cancellation(true);
        else if (test == "malformed") malformed();
        else if (test == "logging") logging();
        else throw std::runtime_error("unknown test case");
        std::cout << "PASS BehaviorTree " << test << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL BehaviorTree: " << error.what() << '\n';
        return 1;
    }
}

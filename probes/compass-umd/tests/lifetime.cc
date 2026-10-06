// SPDX-License-Identifier: BSD-2-Clause
// Origin: EmberBSD, AI-assisted isolated production-method regression.
// Capability/memory/dispatch seams below are test doubles, not a Linux UAPI.
#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <string>
#include <unistd.h>
#include <vector>
#include "status.inc"

static void require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}
// Only fields touched by init are modeled. No layout/ioctl ABI is asserted.
enum { AIPU_IOCTL_QUERY_CAP = 1, AIPU_IOCTL_QUERY_PARTITION_CAP,
       AIPU_IOCTL_DISABLE_TICKCOUNTER, AIPU_IOCTL_DISABLE_TICK_COUNTER };
enum { AIPU_ISA_VERSION_ZHOUYI_V1 = 1, AIPU_ISA_VERSION_ZHOUYI_V2_2 = 3,
       AIPU_ISA_VERSION_ZHOUYI_V3 = 5, AIPU_ISA_VERSION_ZHOUYI_V3_2_0 = 6 };
struct aipu_cap {
  uint32_t partition_cnt = 1, asid_cnt = 0;
  uint64_t asid_base[4]{}, dtcm_base = 0, dtcm_size = 0, gm0_size = 0, gm1_size = 0;
};
struct aipu_partition_cap {
  uint32_t version, cluster_cnt, config;
  struct { uint32_t core_cnt; } clusters[1];
};
struct Memory {
  void set_dev(void *) {}
  void set_asid_base(uint32_t, uint64_t) {}
  void set_asid1(int) {}
  void set_dtcm_info(uint64_t, uint64_t) {}
  bool is_gm_enable() { return false; }
  void set_gm_size(int, uint64_t) {}
};
struct UKMemory {
  static Memory *get_memory(int) { static Memory memory; return &memory; }
};
struct DeviceBase {
  virtual ~DeviceBase() = default;
  int refs = 0, m_dev_type = 0;
  uint32_t m_partition_cnt = 0, m_cluster_cnt = 0, m_core_cnt = 0;
  Memory *m_dram = nullptr;
  std::vector<aipu_partition_cap> m_part_caps;
  void inc_ref_cnt() { refs++; }
  int dec_ref_cnt() { return --refs; }
};
enum { DEV_TYPE_AIPU };
static int device_fd = -1, reused_fd = -1, opens, closes, queries, disables;
static int query_failure;
static bool open_failure, reuse_on_close, zero_partitions, disable_failure;
static int seam_open(const char *name, int flags) {
  require(std::strcmp(name, "/dev/aipu") == 0 && flags == (O_RDWR | O_SYNC), "open arguments");
  opens++;
  if (open_failure) { errno = ENOENT; return -1; }
  device_fd = ::open("/dev/null", O_RDWR);
  require(device_fd >= 0, "fixture open");
  return device_fd;
}
static int seam_close(int fd) {
  closes++;
  require(fd == device_fd, "close owned descriptor number");
  const int result = ::close(fd);
  if (reuse_on_close && reused_fd < 0) {
    reused_fd = ::open("/dev/null", O_RDWR);
    require(reused_fd == fd, "deterministic real descriptor reuse");
  }
  return result;
}
static int seam_ioctl(int fd, int request, void *arg = nullptr) {
  require(fd == device_fd && ::fcntl(fd, F_GETFD) >= 0, "ioctl valid device fd");
  require(reused_fd < 0, "no ioctl on unrelated reused descriptor");
  if (request == AIPU_IOCTL_DISABLE_TICK_COUNTER) {
    disables++;
    return disable_failure ? -1 : 0;
  }
  queries++;
  if (request == query_failure) return -1;
  if (request == AIPU_IOCTL_QUERY_CAP) {
    *static_cast<aipu_cap *>(arg) = aipu_cap{};
    if (zero_partitions) static_cast<aipu_cap *>(arg)->partition_cnt = 0;
  } else {
    require(request == AIPU_IOCTL_QUERY_PARTITION_CAP, "query kind");
    auto *cap = static_cast<aipu_partition_cap *>(arg);
    cap->version = AIPU_ISA_VERSION_ZHOUYI_V3;
    cap->cluster_cnt = cap->clusters[0].core_cnt = 1;
  }
  return 0;
}
#define LOG(...) ((void)0)
#define dump_stack() ((void)0)
#define open seam_open
#define close seam_close
#define ioctl seam_ioctl
namespace aipudrv {
class Aipu : public DeviceBase {
public:
#include "members.inc"
  aipu_ll_status_t init();
  void deinit();
  Aipu();
  ~Aipu() override;
  static Aipu *m_aipu;
  static std::mutex m_tex;
#include "factory.inc"
  aipu_ll_status_t ioctl_cmd(uint32_t cmd, void *) {
    aipu_ll_status_t ret = AIPU_LL_STATUS_SUCCESS;
    int kret = 0;
    switch (cmd) {
#include "tick.inc"
    default: require(false, "unexpected dispatcher operation");
    }
    return ret;
  }
};
Aipu *Aipu::m_aipu = nullptr;
std::mutex Aipu::m_tex;
#include "lifetime.inc"
}
#undef open
#undef close
#undef ioctl

int main(int argc, char **argv) {
  require(argc == 2, "one test case");
  const std::string name = argv[1];
  using aipudrv::Aipu;
  if (name == "initial") {
    Aipu device;
    require(device.m_fd == -1, "header invalid descriptor sentinel");
    device.deinit(); device.deinit();
    require(closes == 0 && disables == 0, "unopened cleanup has no syscall");
    return 0;
  }
  const bool fd_zero = name.find("zero") != std::string::npos;
  if (fd_zero) ::close(STDIN_FILENO);
  if (name == "open-failure") open_failure = true;
  if (name.find("cap-failure") != std::string::npos) query_failure = AIPU_IOCTL_QUERY_CAP;
  if (name.find("partition-failure") != std::string::npos) query_failure = AIPU_IOCTL_QUERY_PARTITION_CAP;
  zero_partitions = name == "empty-cap";
  reuse_on_close = query_failure || zero_partitions;
  DeviceBase *device = nullptr;
  const auto ret = Aipu::get_aipu(&device); // Real factory deletes failed object.
  if (open_failure) {
    require(ret == AIPU_LL_STATUS_ERROR_OPEN_FAIL, "open error preserved");
    require(!device && !Aipu::m_aipu && closes == 0 && queries == 0, "open failure cleanup");
  } else if (query_failure || zero_partitions) {
    const auto expected = query_failure == AIPU_IOCTL_QUERY_PARTITION_CAP ?
        AIPU_LL_STATUS_ERROR_IOCTL_QUERY_CORE_CAP_FAIL : AIPU_LL_STATUS_ERROR_IOCTL_QUERY_CAP_FAIL;
    require(ret == expected, "query error preserved (including fd zero)");
    require(!device && !Aipu::m_aipu, "failed factory resets singleton");
    require(reused_fd >= 0 && ::fcntl(reused_fd, F_GETFD) >= 0, "unrelated reused fd survives destructor");
    require(closes == 1 && disables == 0, "failed init closes exactly once");
    ::close(reused_fd);
  } else {
    require(ret == AIPU_LL_STATUS_SUCCESS && device, "valid open succeeds including fd zero");
    require(!fd_zero || device_fd == 0, "actually tested fd zero");
    auto *aipu = static_cast<Aipu *>(device);
    const bool tick = name.find("tick") != std::string::npos;
    aipu->m_tick_counter.store(tick);
    disable_failure = name == "tick-error";
    if (name != "zero-destructor" && name != "destructor") {
      aipu->deinit(); aipu->deinit();
      require(aipu->m_fd == -1, "deinit invalidates descriptor");
      require(aipu->m_dram == nullptr, "deinit clears memory reference");
      require(aipu->m_tick_counter.load() == (tick && disable_failure),
              "production tick success/error state preserved");
    }
    require(Aipu::put_aipu(&device) && !device, "real release/destructor path");
    require(closes == 1 && disables == (tick ? 1 : 0), "idempotent cleanup and actual tick branch");
    require(::fcntl(device_fd, F_GETFD) == -1 && errno == EBADF, "owned fd closed");
  }
  require(opens == 1, "exactly one device open");
  std::printf("PASS %s\n", name.c_str());
}

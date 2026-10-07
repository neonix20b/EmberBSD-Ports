// SPDX-License-Identifier: BSD-2-Clause
// Origin: EmberBSD, AI-assisted actual-production core-count regression.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

// Only Linux integer typedefs are supplied locally; capability declarations,
// member defaults, LL statuses and the entire getter come from the archive.
using __u32 = uint32_t;
using __u64 = uint64_t;
#include "capability.inc"
#include "status.inc"

class DeviceBase {
public:
    // The fixture exposes production members to seed initialized states.
#include "members.inc"
#include "getter.inc"
};

enum Profile { EMPTY, LEGACY, ONE, TWO, MIXED, MAXIMUM, ZERO_CLUSTER, ZERO_CORE };

static DeviceBase
device(Profile profile)
{
    DeviceBase d;
    if (profile == EMPTY)
        return d;
    if (profile == LEGACY) {
        d.m_part_caps.resize(2);
        d.m_core_cnt = 2; // Real v1/v2 init keeps both topology counts zero.
        return d;
    }
    d.m_partition_cnt = profile == TWO || profile == MIXED ? 2 : 1;
    d.m_cluster_cnt = profile == MAXIMUM ? 8 :
        (profile == TWO || profile == MIXED || profile == ZERO_CORE ? 2 : 1);
    d.m_core_cnt = profile == ZERO_CORE ? 0 : 4;
    d.m_part_caps.resize(d.m_partition_cnt);
    for (uint32_t p = 0; p < d.m_partition_cnt; p++) {
        auto &cap = d.m_part_caps[p];
        cap.cluster_cnt = d.m_cluster_cnt;
        // Accessible storage beyond the logical count demonstrates the old
        // off-by-one without relying on undefined memory contents.
        for (auto &cluster : cap.clusters)
            cluster.core_cnt = 200;
        cap.clusters[0].core_cnt = p == 0 ? d.m_core_cnt : 14;
        cap.clusters[1].core_cnt = p == 0 ? 6 : 16;
        cap.clusters[7].core_cnt = 88;
    }
    if (profile == MIXED)
        d.m_part_caps[1].cluster_cnt = 1;
    if (profile == ZERO_CLUSTER) {
        d.m_cluster_cnt = 0;
        d.m_part_caps[0].cluster_cnt = 0;
    }
    if (profile == ZERO_CORE)
        d.m_part_caps[0].clusters[1].core_cnt = 0;
    return d;
}

struct Case {
    const char *name;
    Profile profile;
    uint32_t partition, cluster;
    aipu_ll_status_t status;
    uint32_t count;
};

static const Case cases[] = {
    {"empty-fastpath", EMPTY, 0, 0, AIPU_LL_STATUS_SUCCESS, 1},
    {"empty-partition", EMPTY, 1, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"empty-cluster", EMPTY, 0, 1, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"legacy-fastpath", LEGACY, 0, 0, AIPU_LL_STATUS_SUCCESS, 2},
    {"legacy-partition", LEGACY, 1, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"legacy-cluster", LEGACY, 0, 1, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"legacy-cluster-maxuint", LEGACY, 0, UINT32_MAX, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"one-fastpath", ONE, 0, 0, AIPU_LL_STATUS_SUCCESS, 4},
    {"partition-equal", ONE, 1, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"partition-larger", ONE, 2, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"partition-maxuint", ONE, UINT32_MAX, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"cluster-equal", ONE, 0, 1, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"cluster-larger", ONE, 0, 2, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"cluster-maxuint", ONE, 0, UINT32_MAX, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"two-last-valid", TWO, 1, 1, AIPU_LL_STATUS_SUCCESS, 16},
    {"two-valid-cluster-zero", TWO, 1, 0, AIPU_LL_STATUS_SUCCESS, 14},
    {"two-valid-partition-zero", TWO, 0, 1, AIPU_LL_STATUS_SUCCESS, 6},
    {"two-partition-equal", TWO, 2, 0, AIPU_LL_STATUS_ERROR_INVALID_PARTITION_ID, 0},
    {"two-cluster-equal", TWO, 1, 2, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
#if SIMULATION
    {"mixed-branch-control", MIXED, 1, 1, AIPU_LL_STATUS_SUCCESS, 16},
#else
    {"mixed-branch-control", MIXED, 1, 1, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
#endif
    {"maximum-last-valid", MAXIMUM, 0, 7, AIPU_LL_STATUS_SUCCESS, 88},
    {"maximum-larger", MAXIMUM, 0, 9, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"zero-cluster-fastpath", ZERO_CLUSTER, 0, 0, AIPU_LL_STATUS_SUCCESS, 4},
    {"zero-cluster-invalid", ZERO_CLUSTER, 0, 1, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0},
    {"zero-core-fastpath", ZERO_CORE, 0, 0, AIPU_LL_STATUS_ERROR_INVALID_OP, 0},
    {"zero-core-valid-cluster", ZERO_CORE, 0, 1, AIPU_LL_STATUS_ERROR_INVALID_OP, 0},
};

static int
run(const Case &test)
{
    DeviceBase d = device(test.profile);
    uint32_t count = UINT32_MAX;
    try {
        auto status = d.get_core_count(test.partition, test.cluster, &count);
        if (status != test.status || count != test.count) {
            std::fprintf(stderr, "FAIL: %s status=%d count=%u (want %d/%u)\n",
                test.name, status, count, test.status, test.count);
            return 1;
        }
    } catch (const std::out_of_range &) {
        std::fprintf(stderr, "FAIL: %s threw out_of_range\n", test.name);
        return 1;
    }
    std::printf("PASS: %s\n", test.name);
    return 0;
}

int
main(int argc, char **argv)
{
    if (argc == 2 && std::strcmp(argv[1], "maximum-equal") == 0)
        return run({"maximum-equal", MAXIMUM, 0, 8, AIPU_LL_STATUS_ERROR_INVALID_CLUSTER_ID, 0});
    if (argc != 1)
        return 2;
    int failed = 0;
    for (const auto &test : cases)
        failed += run(test);
    DeviceBase d = device(ONE);
    for (uint32_t index : {0U, UINT32_MAX}) {
        if (d.get_core_count(index, index, nullptr) != AIPU_LL_STATUS_ERROR_NULL_PTR) {
            std::fprintf(stderr, "FAIL: null output index=%u\n", index);
            failed++;
        } else {
            std::printf("PASS: null output index=%u\n", index);
        }
    }
    std::printf("SIMULATION=%d: 28 cases, %d failed\n", SIMULATION, failed);
    return failed ? 1 : 0;
}

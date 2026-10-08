// SPDX-License-Identifier: BSD-2-Clause
// Origin: EmberBSD, AI-assisted assertions against pinned Linux/AArch64 6.1.1.
#include <cstddef>
#if !defined(REFERENCE_LINUX) && defined(NATIVE_FIRST)
#include <sys/ioctl.h>
#endif
#include <armchina_aipu.h>
#if !defined(REFERENCE_LINUX)
#include <sys/ioctl.h>
static_assert(_IO('Z', 3) == 0x20005a03UL, "native _IO remains native");
static_assert(_IOR('Z', 3, int) == 0x40045a03UL, "native _IOR remains native");
#endif
static_assert(sizeof(void*) == 8, "LP64 wire pointers");
static_assert(AIPU_IOCTL_QUERY_CAP == 0x80c84100UL, "AIPU_IOCTL_QUERY_CAP Linux encoding");
static_assert(AIPU_IOCTL_QUERY_PARTITION_CAP == 0x80804101UL, "AIPU_IOCTL_QUERY_PARTITION_CAP Linux encoding");
static_assert(AIPU_IOCTL_REQ_BUF == 0xc0504102UL, "AIPU_IOCTL_REQ_BUF Linux encoding");
static_assert(AIPU_IOCTL_FREE_BUF == 0x40284103UL, "AIPU_IOCTL_FREE_BUF Linux encoding");
static_assert(AIPU_IOCTL_DISABLE_SRAM == 0x00004104UL, "AIPU_IOCTL_DISABLE_SRAM Linux encoding");
static_assert(AIPU_IOCTL_ENABLE_SRAM == 0x00004105UL, "AIPU_IOCTL_ENABLE_SRAM Linux encoding");
static_assert(AIPU_IOCTL_SCHEDULE_JOB == 0x40904106UL, "AIPU_IOCTL_SCHEDULE_JOB Linux encoding");
static_assert(AIPU_IOCTL_QUERY_STATUS == 0xc0184107UL, "AIPU_IOCTL_QUERY_STATUS Linux encoding");
static_assert(AIPU_IOCTL_KILL_TIMEOUT_JOB == 0x40044108UL, "AIPU_IOCTL_KILL_TIMEOUT_JOB Linux encoding");
static_assert(AIPU_IOCTL_REQ_IO == 0xc0144109UL, "AIPU_IOCTL_REQ_IO Linux encoding");
static_assert(AIPU_IOCTL_GET_HW_STATUS == 0x8004410aUL, "AIPU_IOCTL_GET_HW_STATUS Linux encoding");
static_assert(AIPU_IOCTL_ABORT_CMD_POOL == 0x0000410bUL, "AIPU_IOCTL_ABORT_CMD_POOL Linux encoding");
static_assert(AIPU_IOCTL_DISABLE_TICK_COUNTER == 0x0000410cUL, "AIPU_IOCTL_DISABLE_TICK_COUNTER Linux encoding");
static_assert(AIPU_IOCTL_ENABLE_TICK_COUNTER == 0x0000410dUL, "AIPU_IOCTL_ENABLE_TICK_COUNTER Linux encoding");
static_assert(AIPU_IOCTL_CONFIG_CLUSTERS == 0x4020410eUL, "AIPU_IOCTL_CONFIG_CLUSTERS Linux encoding");
static_assert(AIPU_IOCTL_ALLOC_DMA_BUF == 0x8018410fUL, "AIPU_IOCTL_ALLOC_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_FREE_DMA_BUF == 0x40044110UL, "AIPU_IOCTL_FREE_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_GET_DMA_BUF_INFO == 0xc0204111UL, "AIPU_IOCTL_GET_DMA_BUF_INFO Linux encoding");
static_assert(AIPU_IOCTL_GET_DRIVER_VERSION == 0x80084112UL, "AIPU_IOCTL_GET_DRIVER_VERSION Linux encoding");
static_assert(AIPU_IOCTL_ATTACH_DMA_BUF == 0xc0204113UL, "AIPU_IOCTL_ATTACH_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_DETACH_DMA_BUF == 0x40044114UL, "AIPU_IOCTL_DETACH_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_ALLOC_GRID_ID == 0x80044115UL, "AIPU_IOCTL_ALLOC_GRID_ID Linux encoding");
static_assert(AIPU_IOCTL_ALLOC_GROUP_ID == 0xc0044116UL, "AIPU_IOCTL_ALLOC_GROUP_ID Linux encoding");
static_assert(AIPU_IOCTL_FREE_GROUP_ID == 0x40044117UL, "AIPU_IOCTL_FREE_GROUP_ID Linux encoding");
static_assert(AIPU_IOCTL_GET_CLUSTER_STATUS == 0xc00c4118UL, "AIPU_IOCTL_GET_CLUSTER_STATUS Linux encoding");
static_assert(AIPU_IOCTL_GET_RUNNING_JOB_THREAD_ID == 0x80804119UL, "AIPU_IOCTL_GET_RUNNING_JOB_THREAD_ID Linux encoding");
static_assert(AIPU_IOCTL_ALLOC_SFLAG_ID == 0xc004411aUL, "AIPU_IOCTL_ALLOC_SFLAG_ID Linux encoding");
static_assert(AIPU_IOCTL_FREE_SFLAG_ID == 0x4004411bUL, "AIPU_IOCTL_FREE_SFLAG_ID Linux encoding");
static_assert(AIPU_IOCTL_REBIND_DMA_BUF == 0xc018411cUL, "AIPU_IOCTL_REBIND_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_BIND_DMA_BUF == 0xc018411dUL, "AIPU_IOCTL_BIND_DMA_BUF Linux encoding");
static_assert(AIPU_IOCTL_AIPU_HW_RESET == 0x0000411eUL, "AIPU_IOCTL_AIPU_HW_RESET Linux encoding");
static_assert(AIPU_IOCTL_AIPU_SW_RESET == 0x0000411fUL, "AIPU_IOCTL_AIPU_SW_RESET Linux encoding");
static_assert(sizeof(aipu_config_clusters) == 32 && alignof(aipu_config_clusters) == 4, "aipu_config_clusters layout");
static_assert(sizeof(aipu_partition_cap) == 128 && alignof(aipu_partition_cap) == 8, "aipu_partition_cap layout");
static_assert(sizeof(aipu_cap) == 200 && alignof(aipu_cap) == 8, "aipu_cap layout");
static_assert(sizeof(aipu_rebind_buf_desc) == 24 && alignof(aipu_rebind_buf_desc) == 8, "aipu_rebind_buf_desc layout");
static_assert(sizeof(aipu_bind_buf_desc) == 24 && alignof(aipu_bind_buf_desc) == 8, "aipu_bind_buf_desc layout");
static_assert(sizeof(aipu_buf_desc) == 40 && alignof(aipu_buf_desc) == 8, "aipu_buf_desc layout");
static_assert(sizeof(aipu_buf_request) == 80 && alignof(aipu_buf_request) == 8, "aipu_buf_request layout");
static_assert(sizeof(aipu_dma_buf_request) == 24 && alignof(aipu_dma_buf_request) == 8, "aipu_dma_buf_request layout");
static_assert(sizeof(aipu_dma_buf) == 32 && alignof(aipu_dma_buf) == 8, "aipu_dma_buf layout");
static_assert(sizeof(aipu_job_desc) == 144 && alignof(aipu_job_desc) == 8, "aipu_job_desc layout");
static_assert(sizeof(aipu_job_status_desc) == 56 && alignof(aipu_job_status_desc) == 8, "aipu_job_status_desc layout");
static_assert(sizeof(aipu_job_status_query) == 24 && alignof(aipu_job_status_query) == 8, "aipu_job_status_query layout");
static_assert(sizeof(aipu_io_req) == 20 && alignof(aipu_io_req) == 4, "aipu_io_req layout");
static_assert(sizeof(aipu_hw_status) == 4 && alignof(aipu_hw_status) == 4, "aipu_hw_status layout");
static_assert(sizeof(aipu_cluster_status) == 12 && alignof(aipu_cluster_status) == 4, "aipu_cluster_status layout");
static_assert(sizeof(aipu_running_job_query) == 128 && alignof(aipu_running_job_query) == 4, "aipu_running_job_query layout");
static_assert(sizeof(aipu_id_desc) == 4 && alignof(aipu_id_desc) == 2, "aipu_id_desc layout");
static_assert(offsetof(aipu_cap, asid_base) == 8, "aipu_cap.asid_base offset");
static_assert(offsetof(aipu_cap, is_homogeneous) == 40, "aipu_cap.is_homogeneous offset");
static_assert(offsetof(aipu_cap, dtcm_base) == 48, "aipu_cap.dtcm_base offset");
static_assert(offsetof(aipu_cap, partition_cap) == 72, "aipu_cap.partition_cap offset");
static_assert(offsetof(aipu_partition_cap, info) == 16, "aipu_partition_cap.info offset");
static_assert(offsetof(aipu_partition_cap, cluster_cnt) == 24, "aipu_partition_cap.cluster_cnt offset");
static_assert(offsetof(aipu_partition_cap, clusters) == 28, "aipu_partition_cap.clusters offset");
static_assert(offsetof(aipu_bind_buf_desc, exec_id) == 8, "aipu_bind_buf_desc.exec_id offset");
static_assert(offsetof(aipu_buf_desc, mode) == 36, "aipu_buf_desc.mode offset");
static_assert(offsetof(aipu_buf_request, desc) == 40, "aipu_buf_request.desc offset");
static_assert(offsetof(aipu_dma_buf_request, bytes) == 8, "aipu_dma_buf_request.bytes offset");
static_assert(offsetof(aipu_job_desc, profile_fd) == 80, "aipu_job_desc.profile_fd offset");
static_assert(offsetof(aipu_job_desc, asid0_base) == 136, "aipu_job_desc.asid0_base offset");
static_assert(offsetof(aipu_job_status_desc, pdata) == 16, "aipu_job_status_desc.pdata offset");
static_assert(offsetof(aipu_job_status_query, status) == 8, "aipu_job_status_query.status offset");
static_assert(offsetof(aipu_job_status_query, poll_cnt) == 16, "aipu_job_status_query.poll_cnt offset");
int main() { return 0; }

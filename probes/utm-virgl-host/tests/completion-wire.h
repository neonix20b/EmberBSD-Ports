/* SPDX-License-Identifier: BSD-2-Clause
 * Reduced wire payload seam. The pinned public renderer header is unmodified.
 * The host is little endian; this is not an ABI/endian qualification.
 */
#define VIRTIO_GPU_MAX_CMD_SUBMIT_SIZE (16 * 1024 * 1024)
#define VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY 0x1201
#define g_malloc malloc
#define trace_virtio_gpu_cmd_ctx_submit(...) ((void)0)
#define trace_virtio_gpu_cmd_res_xfer_toh_2d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_xfer_toh_3d(...) ((void)0)
#define trace_virtio_gpu_cmd_res_xfer_fromh_3d(...) ((void)0)
enum virtio_gpu_ctrl_type { response_enum_unused };
struct virtio_gpu_cmd_submit {struct virtio_gpu_ctrl_hdr hdr;uint32_t size,padding;};
struct virtio_gpu_rect {uint32_t x,y,width,height;};
struct virtio_gpu_box {uint32_t x,y,z,w,h,d;};
struct virtio_gpu_transfer_to_host_2d {struct virtio_gpu_ctrl_hdr hdr;struct virtio_gpu_rect r;uint64_t offset;uint32_t resource_id,padding;};
struct virtio_gpu_transfer_host_3d {struct virtio_gpu_ctrl_hdr hdr;struct virtio_gpu_box box;uint64_t offset;uint32_t resource_id,level,stride,layer_stride;};

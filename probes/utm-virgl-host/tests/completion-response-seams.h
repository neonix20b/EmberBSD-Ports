/* SPDX-License-Identifier: BSD-2-Clause. External guest transport observers. */
static struct virtio_gpu_ctrl_hdr response_log[16];
#define virtio_gpu_ctrl_hdr_bswap(h) ((void)(h))
static size_t iov_from_buf(struct iovec *v,unsigned n,size_t off,const void *p,size_t len)
{
 (void)v;(void)n;assert(!off && len>=sizeof(response_log[0]) && responses<16);
 if(expected_detaches && (detaches!=expected_detaches || unmaps!=3))premature=true;
 memcpy(&response_log[responses],p,sizeof(response_log[0]));return len;
}
static void virtqueue_push(void *v,void *e,size_t n){(void)v;(void)e;assert(n>=sizeof(response_log[0]));responses++;}
static void virtio_notify(void *g,void *v){(void)g;(void)v;}

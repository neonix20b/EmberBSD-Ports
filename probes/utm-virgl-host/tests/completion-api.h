/* SPDX-License-Identifier: BSD-2-Clause
 * Backend lookup/submit/transfer/fence boundaries. The five public renderer
 * APIs themselves are compiled from complete unmodified source bodies.
 */
#define TRACE_FUNC() ((void)0)
#define UNUSED __attribute__((unused))
#define VIRGL_TRANSFER_TO_HOST 1
#define VIRGL_TRANSFER_FROM_HOST 2
struct pipe_resource {int unused;};
struct pipe_box {int x,y,z,width,height,depth;};
struct vrend_transfer_info {unsigned level,stride,layer_stride;struct pipe_box *box;uint64_t offset;struct iovec *iovec;unsigned iovec_cnt;bool synchronized;};
struct virgl_resource {struct pipe_resource *pipe_resource;};
struct virgl_context {
 int(*submit_cmd)(struct virgl_context*,void*,uint32_t);
 int(*transfer_3d)(struct virgl_context*,struct virgl_resource*,struct vrend_transfer_info*,int);
 int(*submit_fence)(struct virgl_context*,uint32_t,uint32_t,uint64_t);
};
static int api_status,fence_status;
static unsigned api_calls,global_fence_calls,context_fence_calls,side_effect;
static bool callback_on_failure,block_on_return,oom_on_return,missing_context,missing_resource;
static unsigned forwarded_id,forwarded_ctx,forwarded_transfer_ctx,forwarded_level,forwarded_stride,forwarded_layer,forwarded_direction,forwarded_size;
static uint64_t forwarded_offset,forwarded_fence;
static struct pipe_box forwarded_box;
static void after_call(void)
{
 side_effect=0x51;
 if(block_on_return)active_g->parent_obj.renderer_blocked=1;
 if(oom_on_return){oom=true;virgl_write_async_fence(active_g,88);oom=false;}
}
static int submit_backend(struct virgl_context *ctx,void *buffer,uint32_t size)
{
 (void)ctx;assert(buffer && size==8);forwarded_size=size;api_calls++;after_call();return api_status;
}
static int transfer_backend(struct virgl_context *ctx,struct virgl_resource *res,struct vrend_transfer_info *t,int direction)
{
 (void)res;forwarded_transfer_ctx=ctx?forwarded_ctx:0;api_calls++;forwarded_level=t->level;forwarded_stride=t->stride;forwarded_layer=t->layer_stride;
 forwarded_offset=t->offset;forwarded_box=*t->box;forwarded_direction=direction;
 assert(!t->iovec && !t->iovec_cnt && !t->synchronized);after_call();return api_status;
}
static int context_fence_backend(struct virgl_context *ctx,uint32_t flags,uint32_t ring,uint64_t fence)
{
 (void)ctx;assert(flags==VIRGL_RENDERER_FENCE_FLAG_MERGEABLE && ring==0);
 context_fence_calls++;forwarded_fence=fence;
 if(!fence_status || callback_on_failure)virgl_write_async_context_fence(active_g,7,ring,fence);
 if(block_on_return)active_g->parent_obj.renderer_blocked=1;
 return fence_status;
}
static struct virgl_context backend_ctx={submit_backend,transfer_backend,context_fence_backend};
static struct pipe_resource backend_pipe;
static struct virgl_resource backend_resource={&backend_pipe};
static struct virgl_context *virgl_context_lookup(unsigned id){forwarded_ctx=id;return missing_context?NULL:&backend_ctx;}
static struct virgl_resource *virgl_resource_lookup(unsigned id){forwarded_id=id;return missing_resource?NULL:&backend_resource;}
static int vrend_renderer_transfer_pipe(struct pipe_resource *p,struct vrend_transfer_info *t,int direction){assert(p==&backend_pipe);return transfer_backend(NULL,&backend_resource,t,direction);}
static int vrend_renderer_create_ctx0_fence(uint32_t fence)
{
 global_fence_calls++;forwarded_fence=fence;
 if(!fence_status || callback_on_failure)virgl_write_async_fence(active_g,fence);
 if(block_on_return)active_g->parent_obj.renderer_blocked=1;
 return fence_status;
}
static struct {bool vrend_initialized;struct virgl_renderer_callbacks *cbs;} state={true,&virtio_gpu_3d_cbs};

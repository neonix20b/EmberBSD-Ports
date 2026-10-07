/* SPDX-License-Identifier: BSD-2-Clause. Wait-to-QEMU-barrier causal contract. */
static struct vrend_context wait_contexts[2];
static void wait_retire(uint64_t id,void *data)
{
 struct vrend_context *ctx=data;
 if(ctx->ctx_id)virgl_write_async_context_fence(active_g,ctx->ctx_id,0,id);
 else virgl_write_async_fence(active_g,(uint32_t)id);
 retired_count++;
}
static void wait_add_fence(bool context,uint64_t id)
{
 struct vrend_context *ctx=&wait_contexts[context];
 *ctx=(struct vrend_context){context?7:0,wait_retire,ctx};
 struct vrend_fence *f=calloc(1,sizeof(*f));assert(f);f->ctx=ctx;f->fence_id=id;f->glsyncobj=(void*)1;list_addtail(&f->fences,&vrend_state.fence_list);
}
static void wait_setup(VirtIOGPUGL *gl)
{
 setup(gl);native_count=native_at=native_calls=poll_calls=close_calls=query_calls=retired_count=freed_fences=0;
 use_fd=false;vrend_state.use_egl_fence=false;api_status=fence_status=0;api_calls=global_fence_calls=context_fence_calls=side_effect=0;
 callback_on_failure=block_on_return=oom_on_return=missing_context=missing_resource=false;
 virtio_gpu_virgl_init(&gl->parent_obj);
}
static void qemu_failure_cases(void)
{
 for(unsigned context=0;context<2;context++)for(unsigned mode=0;mode<3;mode++)for(unsigned reset=0;reset<2;reset++) {
  VirtIOGPUGL gl;wait_setup(&gl);VirtIOGPU *g=&gl.parent_obj;add_resources(g);
  uint64_t id=context?(UINT64_C(1)<<40):42;
  command(g,context?3:1,id,context?7:0,true);wait_add_fence(context,id);
  /* A previously queued success must be discarded when the next poll fails. */
  if(context)virgl_write_async_context_fence(g,7,0,id);else virgl_write_async_fence(g,(uint32_t)id);
  vrend_state.use_egl_fence=mode>0;use_fd=mode==2;native_results[0]=mode?EGL_FALSE:GL_WAIT_FAILED;native_count=1;poll_result=-1;poll_errno=EIO;
  virtio_gpu_virgl_fence_poll(g);
  check(gl.fault_latched && gl.classic_state==CL_FAULT_PENDING && !responses && g->inflight==1,"actual failed wait reaches QEMU fault before response or ownership loss");
  check(!retired_count && !detaches && !unmaps,"renderer failure neither retires nor revokes recursively");
  if(reset)virtio_gpu_gl_reset(g);
  aio_bh_call(gl.async_fence_bh);
  check(!responses,"pending success callback cannot escape wait failure or reset");
  if(!gl.fault_latched && !gl.reset_requested)virtio_gpu_virgl_request_fault(g,NULL,0);
  /* Native cleanup may remain blocked after CPU revoke. */
  g->parent_obj.renderer_blocked=1;aio_bh_call(gl.lifecycle_bh);
  check(detaches==2 && unmaps==3 && !premature && !g->inflight && responses==(reset?0:1),"wait fault/reset drains only after all backing revoke");
  if(!reset)check(response_log[0].type==VIRTIO_GPU_RESP_ERR_UNSPEC && response_log[0].fence_id==id && response_log[0].ctx_id==(context?7:0),"failed wait preserves original global/context fence in error response");
  unsigned calls=native_calls+poll_calls;virtio_gpu_virgl_fence_poll(g);check(native_calls+poll_calls==calls,"QEMU stops polling the failed lifecycle");
  g->parent_obj.renderer_blocked=0;virtio_gpu_gl_flushed(&g->parent_obj);aio_bh_call(gl.lifecycle_bh);
  check(freed_fences==1 && !gl.renderer_live,"native cleanup releases failed renderer fence once after revoke");teardown(&gl);
 }
}
static void qemu_success_cases(void)
{
 for(unsigned context=0;context<2;context++) {
  VirtIOGPUGL gl;wait_setup(&gl);VirtIOGPU *g=&gl.parent_obj;uint64_t id=context?(UINT64_C(1)<<40):42;
  command(g,context?3:1,id,context?7:0,true);wait_add_fence(context,id);
  native_results[0]=GL_TIMEOUT_EXPIRED;native_results[1]=GL_CONDITION_SATISFIED;native_count=2;
  virtio_gpu_virgl_fence_poll(g);aio_bh_call(gl.async_fence_bh);check(!gl.fault_latched && !responses && g->inflight==1 && gl.fence_poll->scheduled,"actual timeout keeps pending fence and rearms poll");
  virtio_gpu_virgl_fence_poll(g);aio_bh_call(gl.async_fence_bh);check(!gl.fault_latched && responses==1 && !g->inflight && response_log[0].type==VIRTIO_GPU_RESP_OK_NODATA && response_log[0].fence_id==id,"actual signaled wait completes once with original fence ID");teardown(&gl);
 }
}
int main(void)
{
 klass=(VirtIOGPUClass){virtio_gpu_virgl_cmdq_allowed,virtio_gpu_virgl_cmdq_handoff_allowed,virtio_gpu_virgl_reset_resources,virtio_gpu_virgl_process_cmd,virtio_gpu_virgl_resource_destroy};
#ifdef WAIT_NO_ABI
 VirtIOGPUGL gl;setup(&gl);Error *error=NULL;virtio_gpu_gl_device_realize(&gl.parent_obj,&error);check(error && !base_realizes && !renderer_calls,"missing wait ABI rejects profile before capsets/base realize");check(virtio_gpu_virgl_init(&gl.parent_obj)==-ENOTSUP && !native_live,"missing wait ABI rejects direct profile init");teardown(&gl);
#else
 qemu_failure_cases();qemu_success_cases();check(allocated_handles==deleted_handles,"QEMU wait cases free all lifecycle handles");
#endif
 printf("wait qemu: %u checks, %u failures\n",check_count,fail_count);return fail_count?1:0;
}

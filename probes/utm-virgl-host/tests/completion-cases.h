/* SPDX-License-Identifier: BSD-2-Clause
 * Finite causal tests of reported command/fence errors, not backend detection.
 */
union packet {
 struct virtio_gpu_ctrl_hdr hdr;
 struct {struct virtio_gpu_cmd_submit cs;uint32_t data[2];} submit;
 struct virtio_gpu_transfer_to_host_2d t2d;
 struct virtio_gpu_transfer_host_3d t3d;
};
static const unsigned command_types[]={VIRTIO_GPU_CMD_SUBMIT_3D,VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D,VIRTIO_GPU_CMD_TRANSFER_TO_HOST_3D,VIRTIO_GPU_CMD_TRANSFER_FROM_HOST_3D};
static const int error_statuses[]={EINVAL,-EINVAL,ENOMEM,-ENOMEM,INT_MIN,INT_MAX};
static void completion_setup(VirtIOGPUGL *gl)
{
 setup(gl);virtio_gpu_virgl_init(&gl->parent_obj);
 api_status=fence_status=0;api_calls=global_fence_calls=context_fence_calls=side_effect=0;
 callback_on_failure=block_on_return=oom_on_return=missing_context=missing_resource=false;
 forwarded_id=forwarded_ctx=forwarded_transfer_ctx=forwarded_level=forwarded_stride=forwarded_layer=forwarded_direction=forwarded_size=0;
 forwarded_offset=forwarded_fence=0;memset(response_log,0,sizeof(response_log));
}
static struct virtio_gpu_ctrl_command *enqueue(VirtIOGPU *g,unsigned type,unsigned flags,uint64_t id,union packet *p,struct iovec *v)
{
 memset(p,0,sizeof(*p));p->hdr=(struct virtio_gpu_ctrl_hdr){.type=type,.flags=flags,.fence_id=id,.ctx_id=7};
 size_t size=sizeof(p->hdr);
 if(type==VIRTIO_GPU_CMD_SUBMIT_3D){p->submit.cs.size=8;p->submit.data[0]=42;size=sizeof(p->submit);}
 else if(type==VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D){p->t2d.r=(struct virtio_gpu_rect){1,2,3,4};p->t2d.resource_id=19;p->t2d.offset=UINT64_C(1)<<33;size=sizeof(p->t2d);}
 else {p->t3d.box=(struct virtio_gpu_box){1,2,3,4,5,6};p->t3d.resource_id=19;p->t3d.offset=UINT64_C(1)<<33;p->t3d.level=2;p->t3d.stride=32;p->t3d.layer_stride=256;size=sizeof(p->t3d);}
 *v=(struct iovec){p,size};struct virtio_gpu_ctrl_command *c=command(g,flags,id,7,false);c->elem=(VirtQueueElement){.out_sg=v,.out_num=1};return c;
}
static void expected_wire(unsigned flags,uint64_t id,unsigned error)
{
 check(response_log[0].type==error,"reported error maps to truthful wire status");
 check(response_log[0].flags==(flags&VIRTIO_GPU_FLAG_FENCE) && response_log[0].fence_id==((flags&1)?id:0) && response_log[0].ctx_id==((flags&1)?7:0),"actual response preserves original fence/context or nonfenced header");
}
static void reported_status_cases(void)
{
 for(unsigned kind=0;kind<4;kind++)for(unsigned e=0;e<6;e++)for(unsigned f=0;f<3;f++) {
  unsigned flags=(unsigned[]){0,1,3}[f];uint64_t id=flags==3?(UINT64_C(1)<<40):42;
  VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;add_resources(g);
  union packet p,next;struct iovec v,nv;
  struct virtio_gpu_ctrl_command *c=enqueue(g,command_types[kind],flags,id,&p,&v);
  enqueue(g,VIRTIO_GPU_CMD_SUBMIT_3D,0,99,&next,&nv);
  api_status=error_statuses[e];virtio_gpu_process_cmdq(g);
  check(side_effect==0x51 && api_calls==1,"reported command error stops after one backend side effect");
  check(gl.classic_state==CL_FAULT_PENDING && gl.fault_latched && TAILQ_FIRST(&g->cmdq)==c && TAILQ_EMPTY(&g->fenceq) && !g->inflight,"reported command error retains cmdq ownership before revoke");
  check(!responses && !detaches && !unmaps && !premature && !global_fence_calls && !context_fence_calls,"reported command error never responds or creates fence before revoke");
  /* Baseline cleanup uses the already accepted barrier only after RED has
   * been observed. It does not count as detecting the renderer error. */
  if(!gl.fault_latched)virtio_gpu_virgl_request_fault(g,NULL,0);
  aio_bh_call(gl.lifecycle_bh);
  check(detaches==2 && unmaps==3 && responses==2 && !premature && !g->inflight && TAILQ_EMPTY(&g->cmdq) && TAILQ_EMPTY(&g->fenceq),"reported command error drains once after all backing detaches");
  expected_wire(flags,id,(api_status==ENOMEM || api_status==-ENOMEM)?VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY:VIRTIO_GPU_RESP_ERR_UNSPEC);
  teardown(&gl);
 }
}
static void fence_status_cases(void)
{
 for(unsigned f=0;f<2;f++)for(unsigned e=0;e<6;e++)for(unsigned callback=0;callback<2;callback++) {
  unsigned flags=f?3:1;uint64_t id=f?(UINT64_C(1)<<40):42;
  VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;add_resources(g);
  union packet p;struct iovec v;struct virtio_gpu_ctrl_command *c=enqueue(g,VIRTIO_GPU_CMD_SUBMIT_3D,flags,id,&p,&v);
  fence_status=error_statuses[e];callback_on_failure=callback;virtio_gpu_process_cmdq(g);
  check(api_calls==1 && (f?context_fence_calls:global_fence_calls)==1 && forwarded_fence==id,"fence failure follows one successful command and exact fence ID");
  check(gl.fault_latched && TAILQ_FIRST(&g->cmdq)==c && !g->inflight && TAILQ_EMPTY(&g->fenceq) && !responses,"fence failure retains command without fictitious inflight or OK");
  aio_bh_call(gl.async_fence_bh);
  check(!responses && !detaches,"callback preceding failed fence return cannot retire success");
  if(!gl.fault_latched)virtio_gpu_virgl_request_fault(g,NULL,0);
  aio_bh_call(gl.lifecycle_bh);
  check(responses==1 && !premature && detaches==2 && unmaps==3 && !g->inflight && SLIST_EMPTY(&gl.async_fenceq),"failed fence drains inbox and command after revoke");
  expected_wire(flags,id,(fence_status==ENOMEM || fence_status==-ENOMEM)?VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY:VIRTIO_GPU_RESP_ERR_UNSPEC);
  teardown(&gl);
 }
}
static void success_and_routing_cases(void)
{
 for(unsigned kind=0;kind<4;kind++)for(unsigned f=0;f<3;f++) {
  unsigned flags=(unsigned[]){0,1,3}[f];uint64_t id=flags==3?(UINT64_C(1)<<40):42;
  VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;union packet p;struct iovec v;
  enqueue(g,command_types[kind],flags,id,&p,&v);virtio_gpu_process_cmdq(g);
  check(api_calls==1 && !gl.fault_latched && gl.classic_state==CL_RUNNING,"successful command retains running lifecycle");
  if(!kind)check(forwarded_size==8 && forwarded_ctx==7,"SUBMIT forwards byte payload through actual public API");
  else if(kind==1)check(forwarded_id==19 && forwarded_transfer_ctx==0 && forwarded_level==0 && !forwarded_stride && !forwarded_layer && forwarded_box.z==0 && forwarded_box.depth==1 && forwarded_box.width==3 && forwarded_box.height==4 && forwarded_offset==(UINT64_C(1)<<33) && forwarded_direction==VIRGL_TRANSFER_TO_HOST,"2D transfer retains privileged ctx0 and geometry");
  else check(forwarded_id==19 && forwarded_transfer_ctx==7 && forwarded_level==2 && forwarded_stride==32 && forwarded_layer==256 && forwarded_box.depth==6 && forwarded_offset==(UINT64_C(1)<<33) && forwarded_direction==(kind==2?VIRGL_TRANSFER_TO_HOST:VIRGL_TRANSFER_FROM_HOST),"3D transfers retain context direction and geometry");
  check(TAILQ_EMPTY(&g->cmdq) && (flags?(g->inflight==1 && responses==0):(g->inflight==0 && responses==1)),"successful response or fence follows normal ownership handoff");
  if(flags)aio_bh_call(gl.async_fence_bh);
  expected_wire(flags,id,VIRTIO_GPU_RESP_OK_NODATA);
  check(responses==1 && !g->inflight && TAILQ_EMPTY(&g->fenceq),"successful command completes once");teardown(&gl);
 }
}
static void ordering_and_lookup_cases(void)
{
 for(unsigned fence=0;fence<2;fence++)for(unsigned reset=0;reset<3;reset++) {
  VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;add_resources(g);
  union packet p;struct iovec v;enqueue(g,VIRTIO_GPU_CMD_SUBMIT_3D,3,42,&p,&v);
  if(fence)fence_status=-ENOMEM;else api_status=-ENOMEM;
  block_on_return=true;callback_on_failure=true;virtio_gpu_process_cmdq(g);
  check(gl.fault_latched && !responses,"display block cannot hide returned error");
  if(reset==1)virtio_gpu_gl_reset(g);
  else if(reset==2){virtio_gpu_virgl_request_reset(g);virtio_gpu_virgl_request_fault(g,NULL,VIRTIO_GPU_RESP_ERR_UNSPEC);virtio_gpu_reset(g);}
  aio_bh_call(gl.async_fence_bh);aio_bh_call(gl.lifecycle_bh);
  check(detaches==2 && unmaps==3 && !premature && responses==(reset?0:1) && gl.renderer_live && !g->inflight,"blocked fault or reset revokes CPU backing before response and defers native cleanup");
  if(!reset)expected_wire(3,42,VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY);
  g->parent_obj.renderer_blocked=0;virtio_gpu_gl_flushed(&g->parent_obj);aio_bh_call(gl.lifecycle_bh);teardown(&gl);
 }
 for(unsigned kind=0;kind<4;kind++) {
  VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;union packet p;struct iovec v;
  enqueue(g,command_types[kind],0,42,&p,&v);if(kind)missing_resource=true;else missing_context=true;
  virtio_gpu_process_cmdq(g);check(!api_calls && gl.fault_latched && !responses,"actual public lookup rejection enters barrier without backend call");
  if(!gl.fault_latched)virtio_gpu_virgl_request_fault(g,NULL,0);
  aio_bh_call(gl.lifecycle_bh);expected_wire(0,42,VIRTIO_GPU_RESP_ERR_UNSPEC);teardown(&gl);
 }
 /* Callback OOM can latch first inside submit; preserve the command's more
  * specific returned status while using the already pending barrier. */
 {VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;union packet p;struct iovec v;
  enqueue(g,VIRTIO_GPU_CMD_SUBMIT_3D,0,42,&p,&v);api_status=-ENOMEM;oom_on_return=true;
  virtio_gpu_process_cmdq(g);check(gl.fault_latched && !responses,"prior callback OOM shares pending revoke");aio_bh_call(gl.lifecycle_bh);expected_wire(0,42,VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY);teardown(&gl);}
}
static void legacy_cases(void)
{
 for(unsigned f=0;f<3;f++) {
  unsigned flags=(unsigned[]){0,1,3}[f];VirtIOGPUGL gl;completion_setup(&gl);VirtIOGPU *g=&gl.parent_obj;union packet p;struct iovec v;
  gl.ember_classic_lifecycle=false;enqueue(g,VIRTIO_GPU_CMD_SUBMIT_3D,flags,42,&p,&v);api_status=EINVAL;fence_status=-ENOMEM;virtio_gpu_process_cmdq(g);
  check(!gl.fault_latched && (flags==1?(responses==0 && g->inflight==1):(responses==1 && !g->inflight && response_log[0].type==VIRTIO_GPU_RESP_OK_NODATA)),"profile-off mixed legacy result policy is unchanged");
  gl.ember_classic_lifecycle=true;teardown(&gl);
 }
}
int main(void)
{
 klass=(VirtIOGPUClass){virtio_gpu_virgl_cmdq_allowed,virtio_gpu_virgl_cmdq_handoff_allowed,virtio_gpu_virgl_reset_resources,virtio_gpu_virgl_process_cmd,virtio_gpu_virgl_resource_destroy};
 reported_status_cases();fence_status_cases();success_and_routing_cases();ordering_and_lookup_cases();legacy_cases();
 check(allocated_handles==deleted_handles,"all completion case handles released");
 printf("completion: %u checks, %u failures\n",check_count,fail_count);return fail_count?1:0;
}

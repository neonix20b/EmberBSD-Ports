/* SPDX-License-Identifier: BSD-2-Clause. EmberBSD, AI-assisted causal checks. */
#include "wait-renderer-seams.h"
static unsigned checks,failures;
static void check(bool ok,const char *what){checks++;if(!ok){failures++;fprintf(stderr,"FAIL %s\n",what);}}
static void retired(uint64_t id,void *data){(void)id;(void)data;retired_count++;}
static void fence_cb(void *p,uint32_t f){(void)p;(void)f;}
static void ctx_cb(void *p,uint32_t c,uint32_t r,uint64_t f){(void)p;(void)c;(void)r;(void)f;}
static void *ctx_create(void *p,int i,struct virgl_renderer_gl_ctx_param *q){(void)p;(void)i;(void)q;return (void*)1;}
static void ctx_destroy(void *p,void *c){(void)p;(void)c;}
static int ctx_current(void *p,int i,void *c){(void)p;(void)i;(void)c;return 0;}
static struct virgl_renderer_callbacks callbacks={.version=3,.write_fence=fence_cb,.write_context_fence=ctx_cb,.create_gl_context=ctx_create,.destroy_gl_context=ctx_destroy,.make_current=ctx_current};
static struct vrend_context ctx={7,retired,NULL};
static void setup(void){memset(&vrend_state,0,sizeof(vrend_state));memset(&state,0,sizeof(state));list_inithead(&vrend_state.fence_list);list_inithead(&vrend_state.fence_wait_list);vrend_state.eventfd=-1;vrend_state.ctx0=&ctx;native_count=native_at=native_calls=poll_calls=close_calls=query_calls=retired_count=freed_fences=0;use_fd=poll_retry_once=false;poll_result=0;poll_errno=0;poll_events=0;check(virgl_renderer_ember_classic_init_v1((void*)1,0,&callbacks)==0,"classic init");}
static void add_fence(uint64_t id){struct vrend_fence *f=calloc(1,sizeof(*f));assert(f);f->ctx=&ctx;f->fence_id=id;f->glsyncobj=(void*)1;list_addtail(&f->fences,&vrend_state.fence_list);}
static int run_poll(void){
#ifdef WAIT_PATCHED
 return virgl_renderer_ember_classic_poll_v1();
#else
 virgl_renderer_poll();return 0;
#endif
}
static void failed_wait(bool egl_wait,bool fd,unsigned result,int p_result,int p_errno,short events)
{
 setup();vrend_state.use_egl_fence=egl_wait;use_fd=fd;native_results[0]=result;native_count=1;poll_result=p_result;poll_errno=p_errno;poll_events=events;add_fence(1);
 int status=run_poll();
 check(!retired_count && list_length(&vrend_state.fence_list)==1,"failed wait never produces successful completion");
#ifdef WAIT_PATCHED
 check(status==-EIO && virgl_renderer_ember_classic_wait_status_v1()==-EIO,"wait failure stays sticky");unsigned calls=native_calls+poll_calls;check(run_poll()==-EIO && native_calls+poll_calls==calls,"sticky failure stops further waits");
#else
 (void)status;
#endif
 check(!query_calls,"failed wait exits before query producer");check(close_calls==(fd?1:0),"native fd closed once on error");virgl_renderer_cleanup((void*)1);check(freed_fences==1,"failed fence retained until actual cleanup");
}
int main(void)
{
 failed_wait(false,false,GL_WAIT_FAILED,0,0,0);failed_wait(false,false,0xdead,0,0,0);
 failed_wait(true,false,EGL_FALSE,0,0,0);failed_wait(true,false,0xdead,0,0,0);
 failed_wait(true,true,0,-1,EIO,0);
 short errors[]={POLLERR,POLLNVAL,POLLHUP,POLLIN|POLLERR,POLLIN|POLLNVAL,POLLIN|POLLHUP,POLLOUT};
 for(unsigned i=0;i<sizeof(errors)/sizeof(errors[0]);i++)failed_wait(true,true,0,1,0,errors[i]);
 for(unsigned mode=0;mode<3;mode++)for(unsigned signaled=0;signaled<2;signaled++){
  setup();vrend_state.use_egl_fence=mode>0;use_fd=mode==2;native_results[0]=mode?(signaled?EGL_CONDITION_SATISFIED_KHR:EGL_TIMEOUT_EXPIRED_KHR):(signaled?GL_ALREADY_SIGNALED:GL_TIMEOUT_EXPIRED);native_count=1;poll_result=signaled;poll_events=signaled?POLLIN:0;add_fence(1);int status=run_poll();check(status==0 && retired_count==signaled && list_length(&vrend_state.fence_list)==!signaled,"timeout remains pending and signaled retires");check(query_calls==1,"normal wait preserves query polling");check(close_calls==(mode==2),"fd closed once on timeout/signal");virgl_renderer_cleanup((void*)1);
 }
 /* The actual public context-poll route uses the decoder retirement callback;
  * this does not pretend that SUBMIT directly calls a fence wait. */
 setup();context_poll_object.retire_fences=vrend_decode_ctx_retire_fences;add_fence(1);native_results[0]=GL_WAIT_FAILED;native_count=1;virgl_renderer_context_poll(7);check(!retired_count && list_length(&vrend_state.fence_list)==1,"actual context poll also retains failed wait without completion");virgl_renderer_cleanup((void*)1);
 /* Non-profile callers retain the pre-existing failure completion policy. */
 setup();virgl_renderer_cleanup((void*)1);virgl_renderer_init((void*)1,0,&callbacks);add_fence(1);native_results[0]=GL_WAIT_FAILED;native_count=1;virgl_renderer_poll();check(retired_count==1,"legacy non-profile wait completion policy unchanged");virgl_renderer_cleanup((void*)1);
 /* A signaled prefix followed by failure must remain owned without callback. */
 setup();add_fence(1);add_fence(2);native_results[0]=GL_CONDITION_SATISFIED;native_results[1]=GL_WAIT_FAILED;native_count=2;run_poll();check(!retired_count && list_length(&vrend_state.fence_list)==2,"failed later wait restores signaled prefix without success callbacks");virgl_renderer_cleanup((void*)1);check(freed_fences==2,"prefix and failed fence cleaned exactly once");
#ifdef WAIT_PATCHED
 for(unsigned i=0;i<2;i++){setup();use_fd=vrend_state.use_egl_fence=true;poll_result=-1;poll_errno=i?EAGAIN:EINTR;add_fence(1);check(run_poll()==0 && poll_calls==1 && close_calls==1 && !retired_count && !virgl_renderer_ember_classic_wait_status_v1(),"nonblocking interrupted poll is bounded pending");virgl_renderer_cleanup((void*)1);}
 setup();use_fd=poll_retry_once=true;poll_result=1;poll_events=POLLIN;check(virgl_egl_client_wait_fence(egl,(void*)1,true)==1 && poll_calls==2 && close_calls==1,"blocking helper retries interruption and closes fd once");virgl_renderer_cleanup((void*)1);
 setup();vrend_state.ember_wait_failed=true;check(virgl_renderer_ember_classic_init_v1((void*)1,0,&callbacks)==-EBUSY && virgl_renderer_ember_classic_wait_status_v1()==-EIO,"live reinit cannot clear sticky failure");virgl_renderer_cleanup((void*)1);
 setup();check(!virgl_renderer_ember_classic_wait_status_v1(),"fresh init clears old lifecycle fault");virgl_renderer_cleanup((void*)1);check(virgl_renderer_ember_classic_poll_v1()==-EINVAL,"checked poll rejects cleaned renderer");
#endif
 printf("wait renderer: %u checks, %u failures\n",checks,failures);return failures?1:0;
}

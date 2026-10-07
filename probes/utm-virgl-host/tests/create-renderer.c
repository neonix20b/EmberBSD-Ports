/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted production CREATE/destructor/API ownership seam.
 * All GL, EGL, Metal, GBM and allocators are models, without runtime claims.
 * Selected functions are extracted unmodified. Structures below are reduced
 * field seams, not an ABI/layout proof. Public renderer args/enums are upstream.
 */
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>
#include "virglrenderer.h"
#include "virgl_hw.h"
#include "format-alias.inc"
#include "pipe.inc"
#define UNUSED __attribute__((unused))
#define BIT(n) (1u<<(n))
#define ARRAY_SIZE(a) (sizeof(a)/sizeof((a)[0]))
#define MAX2(a,b) ((a)>(b)?(a):(b))
typedef unsigned GLenum,GLuint,GLbitfield;
typedef void *GLeglImageOES,*MTLTexture_id;
#include "gl-defs.inc"
struct pipe_reference { int count; };
struct pipe_resource { struct pipe_reference reference; unsigned bind,width0,height0,depth0,format,target,last_level,nr_samples,array_size; };
struct vrend_resource {
 struct pipe_resource base; unsigned storage_bits,map_info,gl_id,target,tbo_tex_id,rbo_id,memobj,buffer_storage_flags;
 bool y_0_top,metal_native; char *ptr; void *gbm_bo,*egl_image,*metal_texture,*aux_plane_egl_image[4]; uint64_t size;
};
struct vrend_texture { struct vrend_resource base; struct { int max_lod; } state; int cur_swizzle[4],cur_base,cur_max; };
#include "vrend-args.inc"
#include "storage.inc"
static struct { bool use_gles,use_external_blob,native_share_texture,gbm_layout_feat,finishing; unsigned inferred_gl_caching_type,max_texture_2d_size,max_texture_3d_size,max_texture_cube_size; } vrend_state;
static struct { unsigned flags,internalformat,glformat,gltype; } tex_conv_table[VIRGL_FORMAT_MAX];
static struct { bool vrend_initialized,drm_initialized; } state;
static void *egl;
struct gbm_bo { int dummy; };
#if defined(ENABLE_GBM_ALLOCATION)
static struct { void *device; } gbm_instance,*gbm=&gbm_instance;
#define GBM_BO_USE_LINEAR 1
#define GBM_FORMAT_R8 1
#endif
static bool native_requested,image_feature,fail_texture_struct,fail_custom,fail_wrapper,fail_hash;
static unsigned live_structs,live_host,live_gl,live_egl,live_metal,live_gbm,table_entries,pipe_unrefs;
static unsigned bound_texture,bound_buffer,texture_acquisitions,texture_deletions,external_deletions;
static void *struct_ptr,*host_ptr;
static int renderer_failures,renderer_cases;
static void renderer_check(bool ok,const char *name) { renderer_cases++;if(!ok) { renderer_failures++;printf("FAIL: %s\n",name); } }
static void *texture_calloc(size_t n) { if(fail_texture_struct)return NULL;struct_ptr=calloc(1,n);assert(struct_ptr);live_structs++;return struct_ptr; }
struct virgl_resource { uint32_t res_id,map_info; int fd_type,fd; struct pipe_resource *pipe_resource; const struct iovec *iov; int iov_count; };
static void *modeled_calloc(size_t n,size_t s) {
 if((s==sizeof(struct virgl_resource) && fail_wrapper) || (s!=sizeof(struct virgl_resource) && fail_custom)) return NULL;
 void *p=calloc(n,s);assert(p);if(s!=sizeof(struct virgl_resource)) {host_ptr=p;live_host++;}return p;
}
static void modeled_free(void *p) {
 if(p && p==struct_ptr) {assert(live_structs);live_structs--;struct_ptr=NULL;}
 if(p && p==host_ptr) {assert(live_host);live_host--;host_ptr=NULL;}
 free(p);
}
#define CALLOC_STRUCT(t) texture_calloc(sizeof(struct t))
#define FREE modeled_free
#define free modeled_free
#define calloc modeled_calloc
#define virgl_error(...) ((void)0)
#define virgl_warn(...) ((void)0)
#define virgl_debug(...) ((void)0)
#define debug_texture(...) ((void)0)
#define report_gles_missing_func(...) ((void)0)
#define has_bit(a,b) (((a)&(b))!=0)
static bool has_feature(unsigned f) { return (f==feat_egl_image && image_feature); }
static bool vrend_format_can_multisample(unsigned f) { (void)f;return true; }
static bool vrend_format_can_texture_view(unsigned f) { (void)f;return true; }
static const char *util_format_name(unsigned f) { (void)f;return "modeled format"; }
static unsigned u_minify(unsigned v,unsigned l) { return v>>l?v>>l:1; }
static GLenum tgsitargettogltarget(unsigned t,unsigned n) { (void)n;return t==PIPE_TEXTURE_2D?GL_TEXTURE_2D:GL_TEXTURE_3D; }
static void pipe_reference_init(struct pipe_reference *r,int n) { r->count=n; }
static bool pipe_reference(struct pipe_reference *r,void *null) { assert(!null && r->count==1);return --r->count==0; }
static void glGenTextures(int n,GLuint *id) { assert(n==1);*id=101;live_gl++;texture_acquisitions++; }
static void glBindTexture(GLenum t,GLuint id) { (void)t;bound_texture=id; }
static void glDeleteTextures(int n,const GLuint *id) { assert(n==1 && *id==101 && live_gl);live_gl--;texture_deletions++; }
static void glGenBuffersARB(int n,GLuint *id) { assert(n==1);*id=102;live_gl++; }
static void glBindBufferARB(GLenum t,GLuint id) { (void)t;bound_buffer=id; }
static void glDeleteBuffers(int n,const GLuint *id) { assert(n==1 && *id==102 && live_gl);live_gl--; }
static void glDeleteRenderbuffers(int n,const GLuint *id) { (void)n;(void)id;abort(); }
static void glDeleteMemoryObjectsEXT(int n,const GLuint *id) { (void)n;(void)id;abort(); }
static void glCreateMemoryObjectsEXT(int n,GLuint *id) { (void)n;*id=103; }
#define glGetString(...) NULL
#define glGetError() GL_NO_ERROR
#define GL_NOP(...) ((void)0)
#define glEGLImageTargetTexStorageEXT GL_NOP
#define glEGLImageTargetTexture2DOES GL_NOP
#define glTexStorage2DMultisample GL_NOP
#define glTexStorage3DMultisample GL_NOP
#define glTexImage2DMultisample GL_NOP
#define glTexImage3DMultisample GL_NOP
#define glTexStorage1D(...) ((void)(internalformat))
#define glTexStorage2D(...) ((void)(internalformat))
#define glTexStorage3D(...) ((void)(internalformat),(void)(depth_param))
#define glTexImage1D(...) ((void)(mwidth),(void)(glformat),(void)(gltype))
#define glTexImage2D(...) ((void)(mwidth),(void)(mheight),(void)(glformat),(void)(gltype))
#define glTexImage3D(...) ((void)(mwidth),(void)(mheight),(void)(depth_param),(void)(glformat),(void)(gltype))
#define glTexParameteri GL_NOP
#define glBufferStorage(...) ((void)(buffer_storage_flags))
#define glBufferData(...) ((void)(width))
#define glImportMemoryFdEXT GL_NOP
#define glBufferStorageMemEXT GL_NOP
static bool virgl_egl_metal_create_texture(void *e,struct pipe_resource *p,unsigned f,void **out) { (void)e;(void)p;(void)f;if(!native_requested)return false;*out=(void *)(uintptr_t)201;live_metal++;return true; }
static void *virgl_egl_metal_image_from_texture(void *e,void *tex) { (void)e;assert(tex);live_egl++;return (void *)(uintptr_t)202; }
static void virgl_metal_release_texture(void *tex) { assert(tex==(void *)(uintptr_t)201 && live_metal);live_metal--; }
static void virgl_egl_image_destroy(void *e,void *img) { (void)e;if(img==(void *)(uintptr_t)999)external_deletions++;assert(img==(void *)(uintptr_t)202 && live_egl);live_egl--; }
#if defined(ENABLE_GBM_ALLOCATION)
static unsigned virgl_gbm_convert_flags(unsigned f) { (void)f;return 1; }
static int virgl_gbm_convert_format(unsigned *f,unsigned *out) { (void)f;*out=1;return 0; }
static bool vrend_winsys_different_gpu(void) {return false;}
static bool virgl_gbm_external_allocation_preferred(unsigned bind) { (void)bind;return native_requested; }
static bool virgl_gbm_gpu_import_required(unsigned bind) { (void)bind;return true; }
static bool gbm_device_is_format_supported(void *d,unsigned f,unsigned flags) { (void)d;(void)f;(void)flags;return true; }
static struct gbm_bo *gbm_bo_create(void *d,unsigned w,unsigned h,unsigned f,unsigned flags) { (void)d;(void)w;(void)h;(void)f;(void)flags;live_gbm++;return (struct gbm_bo *)(uintptr_t)203; }
static void gbm_bo_destroy(void *bo) { assert(bo==(void *)(uintptr_t)203 && live_gbm);live_gbm--; }
static unsigned virgl_gbm_get_map_info(void *bo) { (void)bo;return 17; }
static void *virgl_egl_image_from_gbm_bo(void *e,void *bo) { (void)e;assert(bo);live_egl++;return (void *)(uintptr_t)202; }
static int gbm_bo_get_plane_count(void *bo) { (void)bo;return 1; }
static void *virgl_egl_aux_plane_image_from_gbm_bo(void *e,void *bo,int i) { (void)e;(void)bo;(void)i;abort(); }
static int virgl_gbm_export_fd(void *d,unsigned h,int *fd) { (void)d;(void)h;*fd=3;return 0; }
struct modeled_gbm_handle { unsigned u32; };
static struct modeled_gbm_handle gbm_bo_get_handle(void *bo) { (void)bo;return (struct modeled_gbm_handle){1}; }
#endif
void vrend_renderer_resource_destroy(struct vrend_resource *);
#include "renderer.inc"
struct util_hash_table { void *value; uintptr_t key; void (*destroy)(void *); };
static struct util_hash_table table,*virgl_resource_table=&table;
static struct { void (*unref)(struct pipe_resource *,void *);void *data; } pipe_callbacks;
#define VIRGL_RESOURCE_FD_INVALID 0
#define VIRGL_RESOURCE_OPAQUE_HANDLE 7
#define uintptr_to_pointer(v) ((void *)(uintptr_t)(v))
static enum pipe_error util_hash_table_set(struct util_hash_table *t,void *key,void *value) { if(fail_hash)return PIPE_ERROR_OUT_OF_MEMORY;assert(!t->value);t->key=(uintptr_t)key;t->value=value;table_entries++;return PIPE_OK; }
static void *util_hash_table_get(struct util_hash_table *t,void *key) { return t->key==(uintptr_t)key?t->value:NULL; }
static void util_hash_table_remove(struct util_hash_table *t,void *key) { assert(t->key==(uintptr_t)key && t->value && table_entries);t->destroy(t->value);t->value=NULL;t->key=0;table_entries--; }
static void counted_pipe_unref(struct pipe_resource *p,void *d) {pipe_unrefs++;vrend_pipe_resource_unref(p,d);}
#include "resource.inc"
#ifdef CREATE_INTEGRATED
static void integrated_trace(const char *);
#define TRACE_FUNC() integrated_trace(__func__)
#else
#define TRACE_FUNC() ((void)0)
#endif
#include "api.inc"
#undef free
#undef calloc
static void reset_renderer(void) {
 assert(!live_structs && !live_host && !table_entries);
 live_gl=live_egl=live_metal=live_gbm=0;texture_acquisitions=texture_deletions=0;bound_texture=bound_buffer=0;
 memset(&vrend_state,0,sizeof(vrend_state));vrend_state.max_texture_2d_size=vrend_state.max_texture_3d_size=vrend_state.max_texture_cube_size=16384;
 vrend_state.native_share_texture=true;vrend_state.gbm_layout_feat=true;
#if defined(ENABLE_GBM_ALLOCATION)
 gbm_instance.device=(void *)(uintptr_t)1;
#endif
 memset(tex_conv_table,0,sizeof(tex_conv_table));tex_conv_table[1].internalformat=1;
 state.vrend_initialized=true;state.drm_initialized=false;
 fail_texture_struct=fail_custom=fail_wrapper=fail_hash=native_requested=image_feature=false;
 pipe_unrefs=external_deletions=0;table.destroy=virgl_resource_destroy_func;pipe_callbacks.unref=counted_pipe_unref;
}
static struct vrend_renderer_resource_create_args render_args(void) {
 return (struct vrend_renderer_resource_create_args){.target=PIPE_TEXTURE_2D,.format=1,.bind=VIRGL_BIND_RENDER_TARGET,.width=31,.height=17,.depth=1,.array_size=1};
}
static bool no_owned(void) { return !live_structs && !live_host && !live_gl && !live_egl && !live_metal && !live_gbm; }
static void renderer_tests(void) {
 reset_renderer();struct vrend_renderer_resource_create_args a=render_args();a.format=VIRGL_FORMAT_R8_UNORM;
 renderer_check(!vrend_renderer_resource_create(&a,NULL),"actual unknown GL internalformat rejects");
 renderer_check(no_owned() && texture_acquisitions==1 && texture_deletions==1 && !bound_texture,"actual texture failure destroys GL allocation with binding cleared");
 reset_renderer();a=render_args();
 renderer_check(!vrend_renderer_resource_create(&a,(void *)(uintptr_t)999),"external image missing feature rejects");
 renderer_check(no_owned() && !external_deletions && !bound_texture,"external image remains caller-owned on failure");
 reset_renderer();image_feature=true;
 struct pipe_resource *p=vrend_renderer_resource_create(&a,(void *)(uintptr_t)999);
 renderer_check(p && live_gl==1 && live_egl==0,"external image success stores no owned image");vrend_renderer_resource_destroy((struct vrend_resource *)p);
 renderer_check(no_owned() && !external_deletions,"external image remains caller-owned on success destruction");
#if defined(ENABLE_METAL) || defined(ENABLE_GBM_ALLOCATION)
 reset_renderer();native_requested=true;a=render_args();a.bind|=VIRGL_BIND_SCANOUT;
 renderer_check(!vrend_renderer_resource_create(&a,NULL),"actual owned native image missing extension rejects");
 renderer_check(no_owned() && texture_deletions==1 && !bound_texture,"owned native GL/EGL/Metal/GBM failure fully destroyed");
#endif
 reset_renderer();a=render_args();a.target=PIPE_BUFFER;a.bind=VIRGL_BIND_CUSTOM;a.width=23;a.height=1;
 fail_custom=true;renderer_check(!vrend_renderer_resource_create(&a,NULL) && no_owned(),"actual CUSTOM calloc failure fully unwound");
 reset_renderer();p=vrend_renderer_resource_create(&a,NULL);renderer_check(p && live_host==1 && live_structs==1,"actual CUSTOM host memory acquired");vrend_renderer_resource_destroy((struct vrend_resource *)p);renderer_check(no_owned(),"CUSTOM destruction frees owned host pointer");
 reset_renderer();a.bind=VIRGL_BIND_VERTEX_BUFFER;p=vrend_renderer_resource_create(&a,NULL);renderer_check(p && live_gl==1 && !bound_buffer,"actual buffer allocator success clears binding");vrend_renderer_resource_destroy((struct vrend_resource *)p);renderer_check(no_owned(),"buffer success destructor releases GL buffer");
 reset_renderer();a.bind=VIRGL_BIND_STAGING;a.width=1;p=vrend_renderer_resource_create(&a,NULL);renderer_check(p && !live_gl && !live_host,"one-byte staging uses no host storage");vrend_renderer_resource_destroy((struct vrend_resource *)p);renderer_check(no_owned(),"staging wrapper destruction");
 reset_renderer();a=render_args();a.nr_samples=4;p=vrend_renderer_resource_create(&a,NULL);renderer_check(p && ((struct vrend_resource *)p)->base.nr_samples==4,"MSAA guest backing footprint not substituted for resource");vrend_renderer_resource_destroy((struct vrend_resource *)p);
 reset_renderer();a=render_args();a.target=PIPE_MAX_TEXTURE_TYPES;renderer_check(!vrend_renderer_resource_create(&a,NULL) && no_owned(),"actual bad args rejected before allocation");
 reset_renderer();a=render_args();fail_texture_struct=true;renderer_check(!vrend_renderer_resource_create(&a,NULL) && no_owned(),"texture wrapper allocation failure");
 for(int which=0;which<2;which++) {
  reset_renderer();struct virgl_renderer_resource_create_args pub={.handle=11,.target=2,.format=1,.bind=2,.width=31,.height=17,.depth=1,.array_size=1};
  fail_wrapper=which==0;fail_hash=which==1;
  renderer_check(virgl_renderer_resource_create(&pub,NULL,0)==-ENOMEM,"actual API preserves from-pipe wrapper/hash OOM");
  renderer_check(no_owned() && !table_entries && pipe_unrefs==1,"actual from-pipe failure unrefs exactly once with no table entry");
 }
 reset_renderer();struct virgl_renderer_resource_create_args pub={.handle=11,.target=2,.format=1,.bind=2,.width=31,.height=17,.depth=1,.array_size=1};
 renderer_check(virgl_renderer_resource_create(&pub,NULL,0)==0 && table_entries==1 && live_gl==1,"actual API transfers ownership to resource table");
 renderer_check(virgl_renderer_resource_create(&pub,NULL,0)==-EINVAL && table_entries==1 && !pipe_unrefs,"renderer duplicate preserves table resource");
 virgl_resource_remove(11);renderer_check(no_owned() && pipe_unrefs==1 && !table_entries,"ordinary table destruction unrefs exactly once");
}
#ifndef CREATE_INTEGRATED
int main(void) {renderer_tests();printf("Renderer: %d assertions, %d failed\n",renderer_cases,renderer_failures);return renderer_failures?1:0;}
#else
#include "create-qemu.c"
static void integrated_trace(const char *function) {
 if(!strcmp(function,"virgl_renderer_resource_create")) {q_calls++;if(virtio_gpu_find_resource(active_gpu,11))q_published++;}
}
void virgl_renderer_resource_unref(uint32_t id) { q_unrefs++;virgl_resource_remove(id); }
int main(void) {
 for(int dim=2;dim<=3;dim++) for(int mode=0;mode<5;mode++) {
  reset_renderer();VirtIOGPU g;init_gpu(&g);
  fail_wrapper=mode==1;fail_hash=mode==2;fail_texture_struct=mode==3;
  if(mode==4)tex_conv_table[1].internalformat=0;
  send_create(&g,dim,11,0,false);
  if(mode==0) {
   check(response.type==VIRTIO_GPU_RESP_OK_NODATA && table_entries==1 && q_allocated==1 && q_freed==0 && q_published==0,"combined success published once in both registries");
   struct virtio_gpu_resource_unref u={0};u.hdr.type=VIRTIO_GPU_CMD_RESOURCE_UNREF;u.resource_id=11;send_body(&g,&u,sizeof(u));
   check(QTAILQ_EMPTY(&g.reslist) && q_freed==1 && q_unrefs==1 && pipe_unrefs==1 && no_owned(),"combined ordinary UNREF destroys once");
  } else {
   unsigned expected=(mode==1||mode==2)?VIRTIO_GPU_RESP_ERR_OUT_OF_MEMORY:VIRTIO_GPU_RESP_ERR_UNSPEC;
   check(response.type==expected && responses==1 && QTAILQ_EMPTY(&g.reslist) && !table_entries,"combined rejection reaches guest without ghost resource");
   check(no_owned() && q_freed==1 && !q_unrefs && pipe_unrefs==((mode==1||mode==2)?1u:0u),"combined failure conserves ownership without second renderer unref");dispose(&g);
  }
 }
 reset_renderer();VirtIOGPU g;init_gpu(&g);fail_custom=true;struct virtio_gpu_resource_create_3d b=body3(11);b.target=PIPE_BUFFER;b.bind=VIRGL_BIND_CUSTOM;b.width=23;b.height=1;send_body(&g,&b,sizeof(b));
 check(response.type==VIRTIO_GPU_RESP_ERR_UNSPEC && QTAILQ_EMPTY(&g.reslist) && no_owned() && q_freed==1,"combined CUSTOM allocator failure erased errno still rejects");dispose(&g);
 reset_renderer();init_gpu(&g);b=body3(11);b.target=PIPE_MAX_TEXTURE_TYPES;send_body(&g,&b,sizeof(b));
 check(response.type==VIRTIO_GPU_RESP_ERR_UNSPEC && !table_entries && no_owned() && q_freed==1,"combined actual invalid args rejects");dispose(&g);
 printf("Combined: %d assertions, %d failed\n",cases,failures);return failures?1:0;
}
#endif

# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted test seam extension / deliberate causal mutants.
mode = ARGV.shift
if mode == 'verify-patch'
  root, patch = ARGV
  lines = File.readlines(patch)
  target = nil
  hunks = 0
  i = 0
  while i < lines.length
    line = lines[i]
    if line.start_with?('--- a/')
      name = line.delete_prefix('--- a/').strip
      raise 'Invalid delta path' if name.start_with?('/') || name.split('/').include?('..')
      target = File.readlines(File.join(root, name))
    elsif line.start_with?('@@ ')
      match = line.match(/^@@ -(\d+),(\d+) [+](\d+),(\d+) @@/)
      raise 'Unsupported delta hunk' unless match && target
      start, old_count, _, new_count = match.captures.map(&:to_i)
      old = []
      added = 0
      i += 1
      while i < lines.length && !lines[i].start_with?('@@ ', '--- a/')
        case lines[i][0]
        when ' '
          old << lines[i][1..]
          added += 1
        when '-'
          old << lines[i][1..]
        when '+'
          added += 1
        else
          raise 'Unsupported delta hunk line'
        end
        i += 1
      end
      raise 'Non-exact lifecycle hunk position or count' unless
        old.length == old_count && added == new_count &&
        target.slice(start - 1, old_count) == old
      hunks += 1
      next
    end
    i += 1
  end
  raise 'Missing delta hunks' if hunks.zero?
  puts "PASS: #{hunks} exact lifecycle hunk positions"
elsif mode == 'backing'
# SPDX-License-Identifier: BSD-2-Clause
# Extend only existing external seam types; production bodies stay unchanged.
require 'digest'
s=File.read(ARGV[0])
raise 'Accepted C8c1 backing seam drift' unless Digest::SHA256.hexdigest(s) == 'cae307ea09ab388205468b82dc2e8ff5027108247924539612dbdaa0f769c4d7'
s.sub!('#define QTAILQ_REMOVE TAILQ_REMOVE',"#define QTAILQ_REMOVE TAILQ_REMOVE\n#define QTAILQ_FOREACH TAILQ_FOREACH\n#define QTAILQ_EMPTY TAILQ_EMPTY")
s.sub!('typedef struct { QTAILQ_HEAD(,virtio_gpu_virgl_hostmem_region) unmap_done_list; } VirtIOGPUGL;',"#include \"state.inc\"\ntypedef struct { QTAILQ_HEAD(,virtio_gpu_virgl_hostmem_region) unmap_done_list; ClassicLifecycle classic_state; unsigned renderer_call_depth; } VirtIOGPUGL;")
s.sub!('VirtIOGPUGL gl; uint64_t hostmem;', 'VirtIOGPUGL gl; uint64_t hostmem;bool processing_cmdq;struct {QTAILQ_HEAD(,virtio_gpu_simple_resource)bufs;}dmabuf;')
s.sub!('TAILQ_INIT(&g->reslist);TAILQ_INIT(&g->gl.unmap_done_list);', 'TAILQ_INIT(&g->reslist);TAILQ_INIT(&g->gl.unmap_done_list);TAILQ_INIT(&g->dmabuf.bufs);')
s.sub!('int dmabuf_fd; struct iovec *iov;', 'int dmabuf_fd; void *remapped; struct iovec *iov;')
s=s[0...s.index('int main(void)')]
s += <<'C'
static void virtio_gpu_virgl_close_admission(VirtIOGPU *g) {(void)g;}
static void virtio_gpu_virgl_reset_async_fences(VirtIOGPU *g) {(void)g;}
static void virtio_gpu_virgl_drain_commands(VirtIOGPU *g) {(void)g;}
#include "revoke.inc"
int main(void) {
 VirtIOGPU g={0};init(&g);create(&g,7);attach(&g,7,16);
 struct vrend_sub_context sub={0};struct vrend_context ctx={&sub};
 assert(vrend_create_query(&ctx,1,PIPE_QUERY_TIMESTAMP,0,7,0)==0);
 struct vrend_resource *held=pipe_resource;
 virtio_gpu_virgl_revoke(&g);
 check(g.gl.classic_state==CL_REVOKED && !global_resource->iov && !held->iov && maps==unmaps,"actual barrier detaches global and query-held pipe before DMA PROT_NONE");
 check(vrend_check_query(saved_query) && ((struct virgl_host_query_state *)held->ptr)->query_state==VIRGL_QUERY_STATE_DONE,"actual query writes private storage after barrier with guest pages PROT_NONE");
 unref(&g,7);vrend_destroy_query(saved_query);saved_query=NULL;
 check(!global_resource&&!pipe_resource&&maps==unmaps,"actual cleanup drops query ref exactly once");
 init(&g);printf("%d checks, %d failures; actual barrier+mapping+pipe+query\n",checks,failures);return failures?1:0;
}
C
puts s

else
# SPDX-License-Identifier: BSD-2-Clause. Explicit causal mutations of extracted bodies.
path,name=ARGV;s=File.read(path)
def replace_once(s,a,b)
 raise "mutant anchor not unique: #{a[0,60]}" unless s.scan(a).length==1
 s.sub!(a,b)
end
case name
when 'skip-second-detach'
 replace_once(s,"        detach_classic_backing(res);\n    }\n    gl->renderer_call_depth--;", "        if (base->resource_id != 2) { detach_classic_backing(res); }\n    }\n    gl->renderer_call_depth--;")
when 'release-per-resource'
 replace_once(s,"        detach_classic_backing(res);\n    }\n    gl->renderer_call_depth--;", "        detach_classic_backing(res);\n        release_classic_backing(g, res);\n    }\n    gl->renderer_call_depth--;")
when 'lost-oom-latch'
 replace_once(s,'            virtio_gpu_virgl_request_fault(g, NULL, VIRTIO_GPU_RESP_ERR_UNSPEC);','            /* mutant: drop OOM ingress */')
when 'stale-generation'
 replace_once(s,'if (gl->ember_classic_lifecycle && f->generation != gl->generation)', 'if (false)')
when 'thread-sync'
 replace_once(s,'flags &= VIRGL_RENDERER_NATIVE_SHARE_TEXTURE;', 'flags = (flags & VIRGL_RENDERER_NATIVE_SHARE_TEXTURE) | VIRGL_RENDERER_THREAD_SYNC;')
when 'command-guard'
 replace_once(s,'!virtio_gpu_virgl_classic_command(cmd->cmd_hdr.type)', 'false')
when 'fault-handoff'
 replace_once(s,"        vgc->process_cmd(g, cmd);\n        if (vgc->cmdq_allowed && !vgc->cmdq_allowed(g)) {\n            break;\n        }", '        vgc->process_cmd(g, cmd);')
when 'cleanup-under-block'
 replace_once(s,"    if (gl->renderer_live && g->parent_obj.renderer_blocked) {\n        return;\n    }", '    /* mutant: cleanup under block */')
when 'reset-response'
 raise 'missing reset response guards' unless s.scan('if (!gl->reset_requested) {').length==2
 s.gsub!('if (!gl->reset_requested) {','if (true) {')
when 'poll-no-rearm'
 replace_once(s,"        if (virtio_gpu_virgl_cmdq_allowed(g)) {\n            timer_mod(gl->fence_poll,\n                      qemu_clock_get_ms(QEMU_CLOCK_VIRTUAL) + 1);\n        }", '        /* mutant: no persistent rearm */')
when 'producer-poll-gate'
 replace_once(s,"    if (gl->ember_classic_lifecycle &&\n        (g->processing_cmdq || !virtio_gpu_virgl_cmdq_allowed(g))) {\n        return;\n    }", '    /* mutant: public poll bypasses admission */')
when 'resource-precheck'
 replace_once(s,'if (!res->classic_backing_managed || base->iov || base->iov_cnt ||', 'if (false && (!res->classic_backing_managed || base->iov || base->iov_cnt ||')
 replace_once(s,'(res->classic_iov || res->classic_iov_count))) {','(res->classic_iov || res->classic_iov_count)))) {')
when 'blocked-unrealize'
 replace_once(s,"        error_report(\"virtio-gpu: blocked classic unrealize after CPU revoke\");\n        abort();", '        /* mutant: delete device despite live display */')
when 'callback-defaults'
 replace_once(s,'    virtio_gpu_3d_cbs = virtio_gpu_3d_cbs_default;', '    if (gl->generation <= 1) { virtio_gpu_3d_cbs = virtio_gpu_3d_cbs_default; }')
when 'early-query-return'
 replace_once(s,"   vrend_renderer_check_queries();\n\n   if (list_is_empty(&retired_fences))\n      return;", "   if (list_is_empty(&retired_fences))\n      return;\n   vrend_renderer_check_queries();")
else raise "unknown mutant #{name}"
end
File.write(path,s)

end

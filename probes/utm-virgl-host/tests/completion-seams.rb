# SPDX-License-Identifier: BSD-2-Clause
# EmberBSD, AI-assisted reuse of accepted lifecycle external seams.
require 'digest'
s = File.read(ARGV.fetch(0))
raise 'Accepted lifecycle seam drift' unless Digest::SHA256.hexdigest(s) == '629fb059333f23af3b09aa303931c4067eef08178eaa7439e332c87fe112b918'
def once(s, a, b)
  raise "Nonunique seam anchor: #{a[0,60]}" unless s.scan(a).length == 1
  s.sub!(a, b)
end
once(s, 'typedef struct {struct iovec *out_sg;unsigned out_num;} VirtQueueElement;', 'typedef struct {struct iovec *out_sg;unsigned out_num;struct iovec *in_sg;unsigned in_num;} VirtQueueElement;')
once(s, '#include "command.inc"', "#include \"completion-wire.h\"\n#include \"command.inc\"")
start = s.index('static void virtio_gpu_ctrl_response_nodata(VirtIOGPU *g,struct virtio_gpu_ctrl_command *c,uint32_t error)')
finish = s.index('static void dpy_gfx_replace_surface', start)
raise 'Missing response seam' unless start && finish
s[start...finish] = "#include \"completion-response-seams.h\"\n#include \"completion-response.inc\"\n"
start = s.index('int virgl_renderer_create_fence(int fence,uint32_t type)')
finish = s.index('int virgl_renderer_context_create(uint32_t id', start)
raise 'Missing renderer API seam' unless start && finish
s[start...finish] = "#include \"completion-api.h\"\n#include \"completion-api.inc\"\n"
%w[virgl_cmd_submit_3d virgl_cmd_transfer_to_host_2d virgl_cmd_transfer_to_host_3d virgl_cmd_transfer_from_host_3d].each { |name| once(s, "STUB(#{name})", '') }
# Existing tests remain unchanged and compile, but this finite stage executes
# its own status cases; its real payload consumers replace their dispatch seam.
start = s.rindex('int main(void){klass=')
raise 'Missing lifecycle main' unless start
s[start...s.rindex('#endif')] = "#include \"completion-cases.h\"\n"
puts s

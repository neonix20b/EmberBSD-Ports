#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), execute actual upstream lifecycle/selection code.
require 'digest'
require 'fileutils'
require 'open3'
abort 'usage: wlroots-software-node.rb ORIGINAL_NODE_SOURCE ORIGINAL_PARTIAL_INIT_SOURCE NEW_PATCHED_SOURCE NEW_WORK' unless ARGV.length == 4
original, partial, patched = ARGV.first(3).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
fixture = File.join(__dir__, 'wlroots-software-node.c')
inputs = [__FILE__, fixture]
[['original', original], ['partial', partial], ['patched', patched]].each do |name, source|
  dir = work + '/' + name
  FileUtils.mkdir_p(dir)
  fragments = []
  sources = { 'render/egl.c' => %w[egl_init open_render_node wlr_egl_create_with_drm_fd egl_destroy wlr_egl_destroy wlr_egl_dup_drm_fd],
    'render/allocator/allocator.c' => %w[wlr_allocator_autocreate] }
  helper_path = name == 'patched' ? 'util/fd.c' : 'render/allocator/allocator.c'
  (sources[helper_path] ||= []) << 'reopen_drm_node'
  sources.each do |path, functions|
    file = source + '/' + path
    inputs << file
    text = File.read(file)
    functions.each do |function|
      fragment = text[/^[^\n]*\b#{function}\([^)]*\) \{.*?^\}\n/m]
      next if name == 'original' && function == 'egl_destroy' && !fragment
      abort "missing upstream function #{function}" unless fragment
      fragment = fragment.sub('static int reopen_drm_node', 'int reopen_drm_node')
      fragments << fragment
    end
  end
  File.write(dir + '/production.inc', fragments.join("\n"))
  out, status = Open3.capture2e(ENV.fetch('CC', 'cc'), '-std=c11', '-Wall', '-Wextra', '-Werror',
                              '-Wno-unused-function', '-Wno-unused-variable', '-I' + dir, fixture, '-o', dir + '/test')
  File.write(dir + '/compile.log', out)
  abort "fixture compile failed: #{name}" unless status.success?
  cases = case name
          when 'original' then %w[software]
          when 'partial' then %w[software init-failure]
          else %w[software hardware render-only no-render display-reference dup-failure create-failure init-failure init-failure-ref display-failure display-failure-ref no-display open-failure auth-failure]
          end
  cases.each do |scenario|
    out, status = Open3.capture2e(dir + '/test', scenario)
    File.write(dir + '/' + scenario + '.log', out)
    if name == 'original'
      abort 'original code did not reproduce wrong software node selection' unless !status.success? && out.include?('DRM_NODE_PRIMARY')
      puts 'PASS: original production function reproduces the wrong software DRM node (RED)'
    elsif name == 'partial'
      marker = scenario == 'software' ? 'tables[10]' : 'formats == 0'
      abort "prior retry failed to reproduce #{scenario}" unless !status.success? && out.include?(marker)
      puts "PASS: prior retry reproduces #{scenario == 'software' ? 'shared caller/renderer GEM table' : 'partial display/format initialization leak'} (RED)"
    else
      abort "FAIL: #{scenario}" unless status.success?
      puts out
    end
  end
end
File.write(work + '/inputs.sha256', inputs.uniq.map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: production functions under deterministic API boundary doubles; no target renderer was simulated as accepted'

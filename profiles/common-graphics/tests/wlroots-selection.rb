#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), parse real consumer recipes and scanner guards.
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
abort 'usage: wlroots-selection.rb PREPARED_PKGSRC CROSS_MAKECONF NEW_WORK' unless ARGV.length == 3
tree, conf = ARGV.first(2).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'NEW_WORK must be new and absolute' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
make = ENV.fetch('BMAKE', 'bmake')
base = [make, '-C', "#{tree}/wayland/wlroots", "MAKECONF=#{conf}", "WRKOBJDIR=#{work}/work"]

def run(log, *args, ok: true)
  out, status = Open3.capture2e(*args)
  File.write(log, out)
  abort "unexpected command status: #{log}" unless status.success? == ok
  out
end

def check(name)
  abort "FAIL: #{name}" unless yield
  puts "PASS: #{name}"
end
names = %w[PKG_FAIL_REASON PKG_OPTIONS MESON_ARGS TOOL_DEPENDS DEPENDS TOOLBASE EMBERBSD_WAYLAND_SCANNER]
parse = lambda do |name, *args|
  values = run("#{work}/#{name}.log", *base, *args, 'show-vars', "VARNAMES=#{names.join(' ')}").lines.map(&:chomp)
  abort "unexpected parse output: #{name}" unless values.length == names.length
  names.zip(values).to_h
end
minimal = parse.call('minimal', 'EMBERBSD_WLROOTS_PROFILE=headless-gles2')
check('explicit minimal consumer selects GLES2 and no optional dependency closure') do
  minimal['PKG_FAIL_REASON'].empty? && minimal['PKG_OPTIONS'] == 'glesv2' &&
    %w[-Dallocators=gbm -Drenderers=gles2 -Dbackends= -Dsession=disabled -Dxwayland=disabled -Dexamples=false --wrap-mode=nofallback].all? { |arg| Shellwords.split(minimal['MESON_ARGS']).include?(arg) } &&
    !(minimal['TOOL_DEPENDS'] + minimal['DEPENDS']).match?(/glslang|hwdata|seatd|libopeninput|libliftoff|lcms2|cairo|vulkan-loader|xcb-util/)
end
full = parse.call('full', 'EMBERBSD_WLROOTS_PROFILE=full')
check('full recipe retains all supported functions with host-only generator dependencies') do
  full['PKG_FAIL_REASON'].empty? && %w[glesv2 vulkan drm libinput x11 session color-management libliftoff examples xwayland xcb-errors].sort == full['PKG_OPTIONS'].split.sort &&
    full['TOOL_DEPENDS'].include?(':../../graphics/glslang') && full['TOOL_DEPENDS'].include?(':../../sysutils/hwdata') && !full['DEPENDS'].match?(/glslang|hwdata/)
end
native = parse.call('native', 'USE_CROSS_COMPILE=no')
check('native dependency path keeps all recipe defaults and no cross failure') { native['PKG_FAIL_REASON'].empty? && native['PKG_OPTIONS'] == full['PKG_OPTIONS'] }
{
  'unknown-profile' => ['EMBERBSD_WLROOTS_PROFILE=unknown', 'must be full or headless-gles2'],
  'minimal-override' => ['EMBERBSD_WLROOTS_PROFILE=headless-gles2', 'PKG_OPTIONS.wlroots=glesv2 vulkan', 'rejects option overrides'],
  'missing-session' => ['EMBERBSD_WLROOTS_PROFILE=full', 'PKG_OPTIONS.wlroots=-session', 'require the session option'],
  'wrong-scanner' => ['EMBERBSD_WLROOTS_PROFILE=headless-gles2', 'EMBERBSD_WAYLAND_SCANNER=/usr/bin/false', 'must execute and report exactly 1.26.0']
}.each do |name, args|
  message = args.pop
  value = parse.call(name, *args)
  check("rejects #{name}") { value['PKG_FAIL_REASON'].include?(message) }
end
run("#{work}/scanner-positive.log", *base, 'EMBERBSD_WLROOTS_PROFILE=headless-gles2', 'emberbsd-scanner-check')
check('real wlroots pre-configure verifies installed native scanner metadata') { File.size("#{work}/scanner-positive.log") > 0 }
original = File.dirname(File.dirname(minimal['EMBERBSD_WAYLAND_SCANNER']))
clone = "#{work}/changed-scanner"
FileUtils.mkdir_p(clone)
FileUtils.cp_r(original, "#{clone}/prefix")
FileUtils.cp("#{File.dirname(original)}/installed.sha256", "#{clone}/installed.sha256")
File.open("#{clone}/prefix/bin/wayland-scanner", 'a') { |f| f.puts 'changed' }
out = run("#{work}/scanner-negative.log", *base, 'EMBERBSD_WLROOTS_PROFILE=headless-gles2', "EMBERBSD_WAYLAND_SCANNER=#{clone}/prefix/bin/wayland-scanner", 'emberbsd-scanner-check', ok: false)
check('real wlroots pre-configure rejects scanner binary drift') { out.include?('Wayland scanner receipt mismatch:') }
File.write("#{work}/inputs.sha256", [conf, __FILE__, "#{tree}/wayland/wlroots/Makefile", "#{tree}/wayland/wlroots/options.mk"].map { |p| "#{Digest::SHA256.file(p).hexdigest}  #{p}\n" }.join)
puts 'PASS: selection and real native scanner guard only; renderer runtime is a separate target test'

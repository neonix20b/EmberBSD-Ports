#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted). Evaluate the real pkgsrc recipe without building it.
require 'fileutils'
require 'open3'
abort 'Usage: labwc-options.rb PKGSRC MAKECONF NEW_WORK' unless ARGV.size == 3
pkgsrc, config = ARGV.first(2).map { |p| File.realpath(p) }
work = File.expand_path(ARGV.last)
abort 'new absolute work required' unless ARGV.last.start_with?('/') && !File.exist?(work)
FileUtils.mkdir_p(work)
bmake = ENV.fetch('BMAKE', 'bmake')
variables = %w[MESON_ARGS BUILDLINK_TREE MESON_BINARY.wayland-scanner MESON_BINARY.scdoc MESON_BINARY.msgfmt PKG_FAIL_REASON]
[['cross-disabled', 'yes', '-xwayland'], ['cross-enabled', 'yes', 'xwayland'],
 ['native-enabled', 'no', 'xwayland']].each do |name, cross, options|
  command = [bmake, '-C', pkgsrc + '/wayland/labwc', 'MAKECONF=' + config,
             'USE_CROSS_COMPILE=' + cross, 'PKG_OPTIONS.labwc=' + options]
  out, status = Open3.capture2e(*command, *variables.flat_map { |v| ['-v', v] })
  File.write(work + '/' + name + '.log', out)
  abort "recipe evaluation failed: #{out}" unless status.success?
  values = out.lines.map(&:strip)
  abort 'unexpected recipe output' unless values.size == variables.size
  args, tree, scanner, scdoc, msgfmt, failure = values
  abort "recipe failure: #{failure}" unless failure.empty?
  %w[man-pages svg icon labnag nls].each { |feature| abort "missing #{feature}" unless args.split.include?('-D' + feature + '=enabled') }
  expected = options == 'xwayland' ? 'enabled' : 'disabled'
  abort 'ambiguous Xwayland option' unless args.split.grep(/^-Dxwayland=/) == ['-Dxwayland=' + expected]
  if options == 'xwayland'
    %w[xwayland xcb-util-wm].each { |dep| abort "missing selected #{dep}" unless tree.split.include?(dep) }
  end
  if cross == 'yes'
    [scanner, scdoc, msgfmt].each { |tool| abort "missing native generator: #{tool}" unless tool.start_with?('/') && File.executable?(tool) }
  else
    abort 'cross generators leaked into native build' unless [scanner, scdoc, msgfmt].all?(&:empty?)
  end
end
out, status = Open3.capture2e(bmake, '-C', pkgsrc + '/wayland/labwc', 'MAKECONF=' + config,
  'EMBERBSD_WAYLAND_SCANNER=/nonexistent-labwc-scanner', '-v', 'PKG_FAIL_REASON')
File.write(work + '/missing-scanner.log', out)
abort 'missing scanner accepted' unless status.success? && out.include?('existing absolute executable')
puts 'PASS: required features and Xwayland dependencies; explicit native generators only in cross builds; absent scanner rejected'

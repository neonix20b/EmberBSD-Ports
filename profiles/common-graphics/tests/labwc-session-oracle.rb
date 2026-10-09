#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), mutate real session evidence to reject false PASS.
require_relative '../cross/labwc-session-oracle'
abort 'usage: labwc-session-oracle.rb ACCEPTED_GUEST_LOG' unless ARGV.size == 1
log = File.binread(ARGV[0])
abort 'baseline rejected' unless LabwcSessionOracle.check(log, 2)
abort 'partial UTF-8 rejected' unless LabwcSessionOracle.check(log + "\nDEBUG: \xe2\x94\n".b, 2)
before_drag = log.match(/DRAG_CAPTURE: phase=1 rect=(\d+,\d+),640,400/)[1]
cases = {
  'missing pointer entry' => log.gsub(/^DRAG_POINTER:.*\n/, ''),
  'unmoved window' => log.sub(/DRAG_CAPTURE: phase=2 rect=\d+,\d+,640,400/) { "DRAG_CAPTURE: phase=2 rect=#{before_drag},640,400" },
  'repeated shortcut stage' => log.sub('READY_WINDOW: stage=3', 'READY_WINDOW: stage=2'),
  'missing shortcut' => log.sub(/^READY_WINDOW: stage=2.*\n/, ''),
  'missing drag acknowledgement' => log.sub(/^DRAG_ACK.*\n/, ''),
  'missing drag capture' => log.sub(/^DRAG_CAPTURE: phase=2.*\n/, ''),
  'incomplete drag rectangle' => log.sub('pixels=256000', 'pixels=255999'),
  'wrong drag result' => log.sub(/PASS: USB window shortcuts and drag dx=\d+/, 'PASS: USB window shortcuts and drag dx=0'),
  'wrong window state' => log.sub('stage=2 max=1', 'stage=2 max=0'),
  'wrong restore size' => log.sub('size=640x400', 'size=800x600'),
  'missing window frame' => log.sub(/^WINDOW_CAPTURE: stage=2 frame=7 .*\n/, ''),
  'wrong window pixels' => log.sub(/(WINDOW_CAPTURE:.*)rgb=255,0,0/) { Regexp.last_match(1) + 'rgb=0,0,0' },
  'missing elapsed evidence' => log.sub(/^WINDOW_ELAPSED: stage=4.*\n/, ''),
  'short duration' => log.sub(/WINDOW_ELAPSED: stage=4 seconds=\d+/, 'WINDOW_ELAPSED: stage=4 seconds=1'),
  'missing window success' => log.sub(/^PASS: windowed.*\n/, ''),
  'runtime integrity missing' => log.sub('PASS: staged runtime ELF hashes', 'unchecked runtime'),
  'guest cleanup failed' => log.sub('EMBER_LABWC_RESULT=0', 'EMBER_LABWC_RESULT=1'),
  'missing frame' => log.sub(/^CAPTURE: frame=2.*\n/, ''),
  'wrong pixels' => log.sub('rgb=255,0,0', 'rgb=0,0,0'),
  'software renderer' => log.sub('CLIENT_RENDERER: virgl', 'CLIENT_RENDERER: llvmpipe'),
  'software compositor' => log.sub('GL renderer: virgl', 'GL renderer: llvmpipe'),
  'key release missing' => log.sub(/^KEY: code=37 state=0.*\n/, ''),
  'button press missing' => log.sub(/^BUTTON: code=272 state=1.*\n/, ''),
  'failed session' => log.sub('SESSION_EXIT=1,0', 'SESSION_EXIT=1,1'),
  'missing client result' => log.sub(LabwcSessionOracle::CLIENT_PASS, 'client failed'),
  'repeated first session' => log.gsub('SESSION_BEGIN=2', 'SESSION_BEGIN=1'),
  'no guest completion' => log.sub('EMBER_LABWC_END', 'unfinished'),
  'panic' => log + "\npanic: test failure\n"
}
cases.each do |name, changed|
  abort "unchanged fixture: #{name}" if changed == log
  rejected = false
  begin; LabwcSessionOracle.check(changed, 2); rescue RuntimeError; rejected = true; end
  abort "false success: #{name}" unless rejected
end
rejected = false
begin; LabwcSessionOracle.check(log, 1); rescue RuntimeError; rejected = true; end
abort 'missing injection accepted' unless rejected
puts "PASS: accepted log and #{cases.size + 1} false-success controls"

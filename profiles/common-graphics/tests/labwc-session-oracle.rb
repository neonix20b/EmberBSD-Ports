#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), mutate real session evidence to reject false PASS.
require_relative '../cross/labwc-session-oracle'
abort 'usage: labwc-session-oracle.rb ACCEPTED_GUEST_LOG' unless ARGV.size == 1
log = File.read(ARGV[0])
abort 'baseline rejected' unless LabwcSessionOracle.check(log, 2)
cases = {
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

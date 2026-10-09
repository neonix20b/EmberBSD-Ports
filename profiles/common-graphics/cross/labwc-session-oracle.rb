# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), evidence checks shared by runner and regression.
module LabwcSessionOracle
  CLIENT_PASS = 'PASS: four EGL frames, screencopy pixels, USB keyboard/pointer delivery, client cleanup'.freeze
  def self.check(log, injected)
    log = log.delete("\r").gsub(/\e\[[0-9;]*m/, '')
    raise 'kernel panic' if log.include?('panic:')
    raise 'guest preparation failure' if log.include?('EMBER_LABWC_FAILURE=')
    raise 'guest result' unless log.lines.count { |l| l.chomp == 'EMBER_LABWC_RESULT=0' } == 1
    raise 'runtime integrity' unless log.lines.count { |l| l.chomp == 'PASS: staged runtime ELF hashes' } == 2
    raise 'guest did not finish' unless log.lines.count { |l| l.chomp == 'EMBER_LABWC_END' } == 1
    raise 'input injection count' unless injected == 2
    starts = log.scan(/^SESSION_BEGIN=(\d+)$/).flatten
    ends = log.scan(/^SESSION_END=(\d+)$/).flatten
    raise 'session sequence' unless starts == %w[1 2] && ends == %w[1 2]
    %w[1 2].each do |n|
      body = log.split("SESSION_BEGIN=#{n}\n", 2).last.split("SESSION_END=#{n}\n", 2).first
      raise 'session exit' unless body.lines.count { |l| l.chomp == "SESSION_EXIT=#{n},0" } == 1
      raise 'client success missing' unless body.lines.count { |l| l.chomp == CLIENT_PASS } == 1
      raise 'client renderer' unless body.lines.count { |l| l.chomp == 'CLIENT_RENDERER: virgl' } == 1
      raise 'compositor renderer' unless body.scan(/GL renderer: virgl$/).size == 1
      frames = body.scan(/^CAPTURE: frame=([1-4]) size=(\d+x\d+) pixels=1024 rgb=([\d,]+)$/)
      expected = %w[255,0,0 0,255,0 0,0,255 255,255,0]
      raise 'frame sequence/pixels' unless frames == expected.each_with_index.map { |rgb, i| [(i + 1).to_s, '1280x800', rgb] }
      raise 'input readiness' unless body.lines.count { |l| l.chomp == 'READY_INPUT' } == 1
      input = body.split("READY_INPUT\n", 2).last
      raise 'pointer motion absent' unless input.match?(/^MOTION: x=[\d.]+ y=[\d.]+$/)
      %w[KEY BUTTON].zip(%w[37 272]).each do |kind, code|
        raise "#{kind} event sequence" unless input.scan(/^#{kind}: code=#{code} state=([01])$/).flatten == %w[1 0]
      end
    end
    true
  end
end

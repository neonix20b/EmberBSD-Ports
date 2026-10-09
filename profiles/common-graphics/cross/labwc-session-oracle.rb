# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), evidence checks shared by runner and regression.
module LabwcSessionOracle
  CLIENT_PASS = 'PASS: four EGL frames, screencopy pixels, USB keyboard/pointer delivery, client cleanup'.freeze
  def self.check(log, injected)
    log = log.b.delete("\r").gsub(/\e\[[0-9;]*m/, '')
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
      states = body.scan(/^WINDOW_STATE: stage=(\d+) max=([01]) full=([01]) size=(\d+)x(\d+)$/)
      raise 'window state sequence' unless states.size == 4 && states.map { |r| r.first(3) } == [%w[1 0 0], %w[2 1 0], %w[3 0 0], %w[4 0 1]]
      raise 'restored window geometry' unless [states[0], states[2]].all? { |r| r.last(2) == %w[640 400] }
      raise 'maximized geometry' unless states[1][3].to_i >= 1000 && (600..800).cover?(states[1][4].to_i)
      raise 'fullscreen geometry' unless states[3].last(2) == %w[1280 800]
      captures = body.scan(/^WINDOW_CAPTURE: stage=(\d+) frame=(\d+) surface=(\d+x\d+) pixels=1024 rgb=([\d,]+)$/)
      wanted = states.flat_map { |r| (1..15).map { |i| [r[0], i.to_s, r.last(2).join('x'), expected[(i-1)%4]] } }
      raise 'window frames/pixels' unless captures == wanted
      elapsed = body.scan(/^WINDOW_ELAPSED: stage=(\d+) seconds=(\d+)$/)
      raise 'paced window duration' unless elapsed.map(&:first) == %w[1 2 3 4] && elapsed.each_with_index.all? { |r, i| r[1].to_i >= 14*(i+1) } && elapsed.last.last.to_i < 140
      raise 'window cleanup result' unless body.lines.count { |l| l.chomp == 'PASS: windowed/maximized/restored/fullscreen, 60 captured EGL frames' } == 1
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

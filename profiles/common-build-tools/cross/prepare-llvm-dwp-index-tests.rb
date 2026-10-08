#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), preserve legal indexed padding/shared TU tables.
require 'fileutils'

abort "Usage: #{$PROGRAM_NAME} ACCEPTED_RESULTS SOURCE_FIXTURES NEW_WORK" unless ARGV.length == 3
results, fixtures, output = ARGV.map { |p| File.expand_path(p) }
Dir.mkdir(output)
objcopy = ENV.fetch('OBJCOPY')
cc = ENV.fetch('CC')
abort 'Empty object compilation failed' unless system(cc, '-x', 'assembler', '-c', '/dev/null', '-o', "#{output}/empty.o")

def sections(path)
  elf = File.binread(path)
  abort 'Expected ELF64 little endian input' unless elf[0, 6] == "\x7fELF\x02\x01".b
  table = elf[40, 8].unpack1('Q<')
  width, count, strings = elf[58, 6].unpack('v3')
  headers = count.times.map { |i| elf[table + i * width, width] }
  payload = lambda { |h| elf[h[24, 8].unpack1('Q<'), h[32, 8].unpack1('Q<')] }
  names = payload.call(headers.fetch(strings))
  headers.to_h do |h|
    start = h[0, 4].unpack1('V')
    [names[start...names.index("\0", start)], payload.call(h)]
  end
end

def rewrite_index(data)
  words = data.unpack('V*')
  _version, columns, units, slots = words[0, 4]
  ids = 4 + slots * 3
  column = words[ids, columns].index(6) # DW_SECT_STR_OFFSETS, both index versions.
  return data unless column
  offsets = ids + columns
  sizes = offsets + columns * units
  units.times do |row|
    pos = row * columns + column
    offset = words[offsets + pos]
    length = words[sizes + pos]
    words[offsets + pos] = yield(offset, length) unless length.zero?
  end
  words.pack('V*')
end

File.open("#{output}/cases.tsv", 'w') do |cases|
  File.foreach("#{fixtures}/cases.tsv") do |line|
    name, version, types = line.split
    dir = "#{output}/#{name}"
    Dir.mkdir(dir)
    # The runner preserves this copy before forced promotion, so padding
    # tests still exercise an actual width/offset change on DWARF32 tables.
    input = "#{results}/#{name}/input.dwp"
    data = sections(input)
    original = data.fetch('.debug_str_offsets.dwo')
    strings = "\xa5".b * 16 + original
    cu = rewrite_index(data.fetch('.debug_cu_index')) { |offset, _length| offset + 16 }
    updates = { '.debug_cu_index' => cu }
    if data.key?('.debug_tu_index')
      aliases = {}
      updates['.debug_tu_index'] = rewrite_index(data.fetch('.debug_tu_index')) do |offset, length|
        aliases[[offset, length]] ||= begin
          strings << "\xa5".b * 8
          position = strings.bytesize
          strings << original[offset, length]
          position
        end
      end
    end
    strings << "\xa5".b * 7
    updates['.debug_str_offsets.dwo'] = strings
    args = updates.flat_map do |section, bytes|
      path = "#{dir}/#{section}.bin"
      File.binwrite(path, bytes)
      ['--update-section', "#{section}=#{path}"]
    end
    abort "Could not update #{name}" unless system(objcopy, *args, input, "#{dir}/program.dwp")
    FileUtils.cp("#{fixtures}/#{name}/program", "#{dir}/program")
    cases.write(line)
  end
end
puts 'Prepared indexed padding, shared tables and independent TU contributions.'

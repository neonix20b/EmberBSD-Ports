#!/usr/bin/env ruby
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), tiny labelled archive/ELF-inspector fixtures.
require 'tmpdir'
require 'stringio'
require_relative '../cross/rebind-mesa-runtime'

# The CLI keeps its real package pins. Only this production-class contract uses
# tiny synthetic package hashes and a labelled fake readelf, never target code.
mutations = ARGV == ['--mutations']
ARGV.clear if mutations
abort 'usage: mesa-runtime-rebind.rb [--mutations | PRODUCTION_HELPER]' if ARGV.length > 1
load File.realpath(ARGV[0]) if ARGV.length == 1
OWNER = File.expand_path('../cross', __dir__)
LLVM = MesaRuntimeRebind::LLVM
ELF = "\x7fELF\x02\x01".b + "\0".b * 10 + [3, 183].pack('vv')

def hash(path)
  Digest::SHA256.file(path).hexdigest
end

def write(path, text)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, text)
end

def seal(bundle)
  entries = MesaRuntimeRebind.new.inventory(bundle).reject { |name, _| name == 'artifacts.sha256' }
  write(bundle + '/artifacts.sha256', entries.sort.map { |path, sha| "#{sha}  #{path}\n" }.join)
end

def package(f, changes = {})
  entries = {
    '+CONTENTS' => "@cwd /usr/pkg\n@name llvm-23.1.2nb1\nlib/libLLVM.so.23.1\nlib/libLLVM.so\nbin/llvm-config\n@cwd /usr/pkg\n@ignore\n+BUILD_INFO\n",
    'lib/libLLVM.so.23.1' => ELF + 'new LLVM fixture',
    'lib/libLLVM.so' => [:link, 'libLLVM.so.23.1'],
    'bin/llvm-config' => 'package tool, not a target runtime requirement'
  }.merge(changes)
  Zlib::GzipWriter.open(f[:package]) do |gzip|
    Gem::Package::TarWriter.new(gzip) do |tar|
      entries.each do |name, value|
        next if value.nil?
        if value.is_a?(Array)
          tar.add_symlink(name, value[1], 0777)
        else
          tar.add_file_simple(name, 0644, value.bytesize) { |io| io.write(value) }
        end
      end
    end
  end
  f[:policy][:package] = hash(f[:package])
end

def fixture(root)
  f = { root: root, bundle: root + '/accepted', sysroot: root + '/sysroot',
        package: root + '/llvm.tgz', readelf: root + '/fake-readelf', work: root + '/new',
        policy: MesaRuntimeRebind::POLICY.merge(needed: ['libdep.so.1'], rpath: ['/usr/pkg/lib']) }
  write(f[:sysroot] + LLVM, ELF + 'new LLVM fixture')
  File.symlink('libLLVM.so.23.1', f[:sysroot] + '/usr/pkg/lib/libLLVM.so')
  write(f[:sysroot] + '/usr/pkg/bin/llvm-config', 'package tool, not a target runtime requirement')
  %w[libdep.so.1 libEGL.so.1].each { |name| write(f[:sysroot] + '/usr/pkg/lib/' + name, ELF + name) }
  File.symlink('libEGL.so.1', f[:sysroot] + '/usr/pkg/lib/libEGL.so')
  write(f[:sysroot] + '/usr/pkg/share/drirc', 'Mesa configuration')
  write(f[:bundle] + '/bin/mesa-render', ELF + 'renderer')
  FileUtils.cp(OWNER + '/run-mesa-package-tests.sh', f[:bundle])
  f[:policy][:old_dso] = Digest::SHA256.hexdigest(ELF + 'old LLVM fixture')
  f[:policy][:new_dso] = hash(f[:sysroot] + LLVM)
  paths = %w[/usr/pkg/lib/libEGL.so.1 /usr/pkg/lib/libEGL.so /usr/pkg/share/drirc]
  write(f[:bundle] + '/mesa-package-files.sha256', paths.map { |p| "#{hash(f[:sysroot] + p)}  #{p}\n" }.join)
  write(f[:bundle] + '/mesa-package-links.tsv', "/usr/pkg/lib/libEGL.so\tlibEGL.so.1\n")
  runtime = { LLVM => f[:policy][:old_dso] }
  %w[/usr/pkg/lib/libdep.so.1 /usr/pkg/lib/libEGL.so.1].each { |p| runtime[p] = hash(f[:sysroot] + p) }
  write(f[:bundle] + '/runtime-libraries.sha256', runtime.sort.map { |p, sha| "#{sha}  #{p}\n" }.join)
  write(f[:sysroot] + LLVM + '.dynamic', "(NEEDED) [libdep.so.1]\n(SONAME) [libLLVM.so.23.1]\n(RPATH) [/usr/pkg/lib]\n")
  %w[libdep.so.1 libEGL.so.1].each { |name| write(f[:sysroot] + '/usr/pkg/lib/' + name + '.dynamic', '') }
  write(f[:readelf], "#!/usr/bin/env ruby\n# Labelled host fixture, not an ELF tool.\nprint File.read(ARGV.last + '.dynamic')\n")
  File.chmod(0755, f[:readelf])
  package(f)
  Zlib::GzipReader.open(f[:package]) do |gzip|
    Gem::Package::TarReader.new(gzip) do |tar|
      tar.each { |entry| write(f[:sysroot] + '/usr/pkg/pkgdb/llvm-23.1.2nb1/+CONTENTS', entry.read) if entry.full_name == '+CONTENTS' }
    end
  end
  seal(f[:bundle])
  f
end

def invoke(f)
  MesaRuntimeRebind.new.run(f[:bundle], f[:package], f[:sysroot], f[:readelf], f[:work], policy: f[:policy])
end

count = 0
Dir.mktmpdir('mesa-rebind-contract-') do |root|
  root = File.realpath(root)
  f = fixture(root + '/positive')
  before = MesaRuntimeRebind.new.inventory(f[:bundle])
  destination = invoke(f)
  abort 'accepted input changed' unless before == MesaRuntimeRebind.new.inventory(f[:bundle])
  updated = MesaRuntimeRebind.new.manifest(destination + '/runtime-libraries.sha256', installed: true)
  abort 'runtime closure widened' unless updated.keys.sort == [LLVM, '/usr/pkg/lib/libdep.so.1', '/usr/pkg/lib/libEGL.so.1'].sort
  abort 'runtime DSO not rebound' unless updated[LLVM] == f[:policy][:new_dso]
  before.each do |name, sha|
    next if %w[artifacts.sha256 runtime-libraries.sha256].include?(name)
    abort 'accepted artifact replaced' unless hash(destination + '/' + name) == sha
  end
  abort 'original runtime not retained' unless hash(destination + '/runtime-rebind/original-runtime-libraries.sha256') == before['runtime-libraries.sha256']
  abort 'full package receipt missing tool' unless JSON.parse(File.read(f[:work] + '/llvm-payload.json')).key?('bin/llvm-config')
  abort 'private payload receipt copied into target bundle' if File.exist?(destination + '/llvm-payload.json')
  count += 1

  cases = {
    'accepted binary drift' => ['bundle inventory/hash mismatch', ->(x) { write(x[:bundle] + '/bin/mesa-render', 'damaged') }],
    'unrecorded bundle file' => ['bundle inventory/hash mismatch', ->(x) { write(x[:bundle] + '/extra', 'unrecorded') }],
    'bundle symlink' => ['nonregular bundle artifact', ->(x) { File.symlink('mesa-render', x[:bundle] + '/bin/link') }],
    'manifest traversal' => ['unsafe path', ->(x) { File.write(x[:bundle] + '/artifacts.sha256', "#{'0' * 64}  ../escape\n") }],
    'duplicate manifest' => ['duplicate manifest path', ->(x) { File.open(x[:bundle] + '/artifacts.sha256', 'a') { |io| io.write(File.readlines(x[:bundle] + '/artifacts.sha256').first) } }],
    'old version gate' => ['unsupported old LLVM', ->(x) { x[:policy][:old_dso] = '0' * 64 }],
    'archive hash gate' => ['unsupported LLVM package hash', ->(x) { x[:policy][:package] = '0' * 64 }],
    'new DSO gate' => ['unsupported new LLVM DSO', ->(x) { x[:policy][:new_dso] = '0' * 64 }],
    'archive identity' => ['package identity/prefix mismatch', ->(x) { package(x, '+CONTENTS' => "@cwd /usr/pkg\n@name llvm-24.1.0\n") }],
    'archive cwd' => ['package identity/prefix mismatch', ->(x) { package(x, '+CONTENTS' => "@cwd /usr/pkg\n@cwd /outside\n@name llvm-23.1.2nb1\n") }],
    'contents payload set' => ['+CONTENTS payload mismatch', ->(x) { package(x, '+CONTENTS' => "@cwd /usr/pkg\n@name llvm-23.1.2nb1\nlib/libLLVM.so.23.1\n") }],
    'archive traversal' => ['unsafe path', ->(x) { package(x, '../escape' => 'bad') }],
    'archive absolute path' => ['unsafe path', ->(x) { package(x, '/escape' => 'bad') }],
    'unowned package link' => ['unowned/cyclic package link', ->(x) { File.unlink(x[:sysroot] + '/usr/pkg/lib/libLLVM.so'); File.symlink('libdep.so.1', x[:sysroot] + '/usr/pkg/lib/libLLVM.so'); package(x, 'lib/libLLVM.so' => [:link, 'libdep.so.1']) }],
    'escaping package link' => ['unsafe package symlink', ->(x) { package(x, 'lib/libLLVM.so' => [:link, '/outside']) }],
    'package tool drift' => ['package file mismatch: bin/llvm-config', ->(x) { write(x[:sysroot] + '/usr/pkg/bin/llvm-config', 'damaged') }],
    'package DSO drift' => ['package file mismatch: lib/libLLVM.so.23.1', ->(x) { write(x[:sysroot] + LLVM, ELF + 'damaged') }],
    'same-byte link drift' => ['package symlink mismatch', ->(x) { File.unlink(x[:sysroot] + '/usr/pkg/lib/libLLVM.so'); File.symlink('./libLLVM.so.23.1', x[:sysroot] + '/usr/pkg/lib/libLLVM.so') }],
    'regular replaced by symlink' => ['symlink in installed path', ->(x) { File.rename(x[:sysroot] + '/usr/pkg/bin/llvm-config', x[:root] + '/outside'); File.symlink(x[:root] + '/outside', x[:sysroot] + '/usr/pkg/bin/llvm-config') }],
    'non-LLVM runtime drift' => ['unchanged runtime drift', ->(x) { write(x[:sysroot] + '/usr/pkg/lib/libdep.so.1', ELF + 'changed') }],
    'Mesa config drift' => ['final canonical sysroot verification failed', ->(x) { write(x[:sysroot] + '/usr/pkg/share/drirc', 'changed') }],
    'Mesa link drift' => ['final canonical sysroot verification failed', ->(x) { File.unlink(x[:sysroot] + '/usr/pkg/lib/libEGL.so'); File.symlink('./libEGL.so.1', x[:sysroot] + '/usr/pkg/lib/libEGL.so') }],
    'NEEDED existing provider' => ['LLVM NEEDED changed', ->(x) { File.open(x[:sysroot] + LLVM + '.dynamic', 'a') { |io| io.puts('(NEEDED) [libEGL.so.1]') } }],
    'NEEDED expansion' => ['LLVM NEEDED changed', ->(x) { File.open(x[:sysroot] + LLVM + '.dynamic', 'a') { |io| io.puts('(NEEDED) [libnew.so.1]') } }],
    'closure expansion' => ['expanded package dependency closure', ->(x) { write(x[:sysroot] + '/usr/pkg/lib/libnew.so.1', ELF); write(x[:sysroot] + '/usr/pkg/lib/libdep.so.1.dynamic', '(NEEDED) [libnew.so.1]') }],
    'unresolved dependency' => ['unresolved dependency', ->(x) { write(x[:sysroot] + '/usr/pkg/lib/libdep.so.1.dynamic', '(NEEDED) [libabsent.so.1]') }],
    'relative RPATH' => ['relative/traversing ELF search path', ->(x) { File.open(x[:sysroot] + LLVM + '.dynamic', 'a') { |io| io.puts('(RUNPATH) [relative]') } }],
    'registered contents drift' => ['installed LLVM +CONTENTS mismatch', ->(x) { write(x[:sysroot] + '/usr/pkg/pkgdb/llvm-23.1.2nb1/+CONTENTS', 'changed') }],
    'wrong SONAME' => ['LLVM SONAME/RPATH changed', ->(x) { write(x[:sysroot] + LLVM + '.dynamic', "(NEEDED) [libdep.so.1]\n(SONAME) [libOTHER.so]\n(RPATH) [/usr/pkg/lib]\n") }],
    'existing destination' => ['NEW_WORK must be a new absolute path', ->(x) { Dir.mkdir(x[:work]) }],
    'dangling destination' => ['NEW_WORK must be a new absolute path', ->(x) { File.symlink('missing', x[:work]) }],
    'relative destination' => ['NEW_WORK must be absolute', ->(x) { x[:work] = 'relative' }],
    'destination overlap' => ['NEW_WORK overlaps an input', ->(x) { x[:work] = x[:bundle] + '/new' }],
    'symlink destination parent' => ['NEW_WORK parent must be canonical', ->(x) { File.symlink(x[:root], x[:root] + '/alias'); x[:work] = x[:root] + '/alias/new' }]
  }
  cases.each_with_index do |(name, (message, mutate)), index|
    f = fixture(root + "/negative-#{index}")
    mutate.call(f)
    begin
      invoke(f)
      abort "accepted negative: #{name}"
    rescue ArgumentError => error
      abort "wrong rejection for #{name}: #{error.message}" unless error.message.include?(message)
    end
    abort "published failed bundle: #{name}" if File.exist?(f[:work] + '/bundle')
    count += 1
  end
end
puts "PASS: #{count} runtime rebind contracts (synthetic package/ELF-inspector fixtures; no target execution)"

if mutations
  source = File.read(OWNER + '/rebind-mesa-runtime.rb')
  guards = {
    'accepted binary drift' => "    fail!('bundle inventory/hash mismatch') unless before.reject { |name, _| name == 'artifacts.sha256' } == expected\n",
    'old version gate' => "    fail!('unsupported old LLVM runtime') unless runtime[LLVM] == policy.fetch(:old_dso)\n",
    'archive hash gate' => "    fail!('unsupported LLVM package hash') unless sha(@package) == policy.fetch(:package)\n",
    'package tool drift' => '            fail!("package file mismatch: #{name}") unless sha(target) == digest.hexdigest' + "\n",
    'Mesa config drift' => "    fail!('final canonical sysroot verification failed') unless status.success?\n",
    'NEEDED existing provider' => "        fail!('LLVM NEEDED changed') unless info['needed'].sort == @policy.fetch(:needed).sort\n"
  }
  Dir.mktmpdir('mesa-rebind-mutants-') do |directory|
    directory = File.realpath(directory)
    FileUtils.cp(OWNER + '/run-mesa-package-tests.sh', directory)
    guards.each_with_index do |(name, guard), index|
      abort "mutation guard missing: #{name}" unless source.scan(guard).length == 1
      mutant = directory + "/mutant-#{index}.rb"
      altered = source.sub(guard, '')
      # The package pin is checked twice to catch input drift; remove both checks
      # only for this mutation so it proves the revision gate itself is causal.
      altered = altered.sub(' && sha(@package) == policy.fetch(:package)', '') if name == 'archive hash gate'
      File.write(mutant, altered)
      out, err, status = Open3.capture3(RbConfig.ruby, File.realpath(__FILE__), mutant)
      abort "noncausal mutation result: #{name}\n#{out}\n#{err}" unless !status.success? && (out + err).include?("accepted negative: #{name}")
      puts "PASS: removed guard accepts #{name}; contract kills mutant"
    end
  end
end

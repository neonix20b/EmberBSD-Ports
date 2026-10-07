#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed target binary-tool consumers.
set -eu
[ "$#" = 1 ] || { echo "Usage: $0 NEW_WORK" >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] && [ "$(uname -p)" = aarch64 ] || {
    echo 'Run on an AArch64 EmberBSD target' >&2; exit 2;
}
cc=${CC:-/usr/pkg/gcc16/bin/gcc}
cxx=${CXX:-/usr/pkg/gcc16/bin/g++}
prefix=${BINUTILS_PREFIX:-/usr/pkg}
tools=$prefix/gnu/bin
mkdir "$1"
cd "$1"
work=$(pwd -P)
case "$work:$tools" in *[!a-zA-Z0-9_./:-]*) echo 'Use paths without shell metacharacters' >&2; exit 2;; esac
for tool in as ld ar ranlib nm readelf objdump objcopy strip addr2line; do
    [ -x "$tools/$tool" ] || { echo "Missing $tools/$tool" >&2; exit 1; }
    "$tools/$tool" --version > "$tool.version"
    grep -q '2\.47' "$tool.version"
done
# The accepted GCC16 bootstrap package has absolute --with-as/--with-ld
# paths, which override -B. Select these installed GNU programs explicitly
# through standard GCC specs for this test; do not modify the compiler.
# Direct ELF linking is sufficient here; LTO/collect2 is a separate gate.
"$cc" -dumpspecs > installed.specs
awk -v assembler="$tools/as" '
    /^\*invoke_as:$/ { block = 1; print; next }
    block && /^$/ { block = 0; print; next }
    block { changed += sub(/(^|[[:space:]])as[[:space:]]/, " " assembler " "); print }
    END { if (changed != 1) exit 1 }
' installed.specs > selected-tools.specs
printf '*linker:\n%s\n\n' "$tools/ld" >> selected-tools.specs
run_cc() { "$cc" -specs="$work/selected-tools.specs" "$@"; }
run_cxx() { "$cxx" -specs="$work/selected-tools.specs" "$@"; }
cat > answer.c <<'C'
struct answer { int value; const char *label; };
int answer(void)
{
    struct answer a = { 42, "ember-binutils" };
    return a.value;
}
C
cat > main.c <<'C'
#include <stdio.h>
extern int answer(void);
int main(void) { int value = answer(); printf("%d\n", value); return value != 42; }
C

# GCC must actually invoke the installed assembler and linker under test.
run_cc -v -O0 -gdwarf-5 -c answer.c -o answer.o 2> compiler.log
grep -F "$tools/as" compiler.log
"$tools/ar" cr libanswer.a answer.o
"$tools/ranlib" libanswer.a
"$tools/ar" t libanswer.a > archive.txt
grep -qx 'answer.o' archive.txt
run_cc -v -Wl,-v -O0 -gdwarf-5 -no-pie main.c libanswer.a -o static-consumer 2> linker.log
grep -F "$tools/ld" linker.log
[ "$(./static-consumer)" = 42 ]
"$tools/readelf" -h static-consumer > elf.txt
grep -q 'AArch64' elf.txt
"$tools/readelf" --debug-dump=info static-consumer > dwarf.txt
grep -Eq 'Version:[[:space:]]+5' dwarf.txt
"$tools/nm" --defined-only static-consumer > symbols.txt
address=$(awk '$3 == "answer" { print $1 }' symbols.txt)
[ -n "$address" ]
"$tools/addr2line" -f -e static-consumer "$address" > location.txt
grep -qx answer location.txt
grep -Eq '/answer\.c:[1-9][0-9]*$' location.txt
"$tools/objdump" -d static-consumer > disassembly.txt
grep -q '<answer>:' disassembly.txt
echo 'PASS: GCC16 selected GNU assembler/linker, archive consumer and DWARF5 source lookup'

run_cc -O0 -gdwarf-5 -gdwarf64 -c answer.c -o dwarf64.o
"$tools/readelf" --debug-dump=info dwarf64.o > dwarf64.txt
grep -q '64-bit' dwarf64.txt
"$tools/readelf" -x .debug_line dwarf64.o > line32-header.txt
line_length=$(awk '$1 == "0x00000000" { print $2 }' line32-header.txt)
[ -n "$line_length" ] && [ "$line_length" != ffffffff ]
"$tools/addr2line" -f -e dwarf64.o 0 > dwarf64-location.txt
grep -qx answer dwarf64-location.txt
grep -Eq '/answer\.c:[1-9][0-9]*$' dwarf64-location.txt
# GCC normally lets AArch64 gas emit a DWARF32 line table even for a
# DWARF64 CU. Also check GCC's own DWARF64 line table as a control.
run_cc -O0 -gdwarf-5 -gdwarf64 -gno-as-loc-support -c answer.c -o line64.o
"$tools/readelf" -x .debug_line line64.o > line64-header.txt
grep -Eq '0x00000000[[:space:]]+ffffffff' line64-header.txt
"$tools/addr2line" -f -e line64.o 0 > line64-location.txt
grep -qx answer line64-location.txt
grep -Eq '/answer\.c:[1-9][0-9]*$' line64-location.txt
"$tools/objcopy" --only-keep-debug static-consumer static-consumer.debug
"$tools/objcopy" --strip-debug --add-gnu-debuglink=static-consumer.debug static-consumer split-consumer
"$tools/readelf" -S split-consumer > split-sections.txt
grep -q '\.gnu_debuglink' split-sections.txt
if grep -q '\.debug_info' split-sections.txt; then exit 1; fi
"$tools/addr2line" -f -e static-consumer.debug "$address" > split-location.txt
cmp location.txt split-location.txt
"$tools/strip" --strip-unneeded split-consumer
[ "$(./split-consumer)" = 42 ]
echo 'PASS: DWARF64 with both line-table formats, split debug data and stripped executable'

cat > library.cc <<'CXX'
#include <stdexcept>
extern "C" void throw_answer() { throw std::runtime_error("42"); }
CXX
cat > consumer.cc <<'CXX'
#include <stdexcept>
#include <string>
extern "C" void throw_answer();
int main() {
    try { throw_answer(); }
    catch (const std::runtime_error &e) { return std::string(e.what()) != "42"; }
    return 1;
}
CXX
run_cxx -std=c++20 -fPIC -shared library.cc -Wl,-soname,libanswer.so.1 -o libanswer.so.1
ln -s libanswer.so.1 libanswer.so
run_cxx -std=c++20 consumer.cc -L. -lanswer -Wl,-rpath,"$work" -Wl,-rpath,/usr/pkg/gcc16/lib -o shared-consumer
./shared-consumer
ldd shared-consumer > runtime.txt
grep -E '/usr/pkg/gcc16/lib/(\./)*libstdc\+\+\.so' runtime.txt
grep -E '/usr/pkg/gcc16/lib/(\./)*libgcc_s\.so' runtime.txt
"$tools/strip" --strip-unneeded libanswer.so.1
./shared-consumer
echo 'PASS: GNU-linked C++20 exceptions across a stripped DSO with the common GCC16 runtime'

# CTF is emitted and merged by the installed GNU tools, independently of
# NetBSD's DWARF-to-CTF kernel build path.
run_cc -O0 -gctf -c answer.c -o ctf-answer.o
run_cc -O0 -gctf -c main.c -o ctf-main.o
run_cc ctf-answer.o ctf-main.o -o ctf-consumer
[ "$(./ctf-consumer)" = 42 ]
"$tools/readelf" --ctf=.ctf ctf-consumer > ctf.txt
grep -q 'struct answer' ctf.txt
grep -q 'value' ctf.txt
grep -q 'label' ctf.txt
echo 'PASS: GCC16 CTF emission, GNU ld type merge and readelf decoding'

cat > catalog.c <<'C'
#include <libintl.h>
#include <locale.h>
#include <string.h>
int main(int argc, char **argv)
{
    const char *original = "%s: no symbols";
    const char *translated;
    if (argc != 2 || setlocale(LC_ALL, "ru_RU.UTF-8") == 0)
        return 1;
    if (bindtextdomain("binutils", argv[1]) == 0 ||
        bind_textdomain_codeset("binutils", "UTF-8") == 0)
        return 2;
    translated = dgettext("binutils", original);
    return translated[0] == '\0' || strcmp(translated, original) == 0;
}
C
run_cc catalog.c -lintl -o catalog
LC_ALL=ru_RU.UTF-8 LANGUAGE=ru ./catalog "$prefix/share/locale"
LC_ALL=C "$tools/nm" "$prefix/bin/greadelf" > catalog-english.txt 2>&1
grep -q ': no symbols$' catalog-english.txt
LC_ALL=ru_RU.UTF-8 LANGUAGE=ru "$tools/nm" "$prefix/bin/greadelf" > catalog-translated.txt 2>&1
if cmp -s catalog-english.txt catalog-translated.txt; then exit 1; fi
if grep -q ': no symbols$' catalog-translated.txt; then exit 1; fi
echo 'PASS: installed translation catalog decoded by the NetBSD libintl API'

cat > unresolved.c <<'C'
extern int missing_ember_symbol(void);
int main(void) { return missing_ember_symbol(); }
C
if run_cc unresolved.c -o unresolved > unresolved.log 2>&1; then
    echo 'Unresolved symbol unexpectedly linked' >&2; exit 1
fi
grep -q 'missing_ember_symbol' unresolved.log
echo 'PASS: unresolved-symbol link failure remains visible'

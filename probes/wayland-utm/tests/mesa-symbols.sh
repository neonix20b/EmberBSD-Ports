#!/bin/sh
# Origin: EmberBSD; AI-assisted regression of the upstream symbol checker.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: sh mesa-symbols.sh MESA_SOURCE NEW_WORK' >&2; exit 2; }
[ "$(uname -s)" = NetBSD ] || { echo 'Native NetBSD symbol policy required.' >&2; exit 2; }
source_dir=$(CDPATH= cd -- "$1" && pwd)
work=$2
python=${PYTHON:-/usr/pkg/bin/python3.14}
mkdir "$work"
# Substitute nm's output boundary; execute upstream symbols-check.py unchanged.
cat > "$work/nm" <<'END_NM'
#!/bin/sh
[ "$1" = -gP ] && [ "$#" -eq 2 ] || exit 2
cat "$2"
END_NM
chmod 755 "$work/nm"
printf 'public_api\n' > "$work/api"
printf 'public_api T 100 4\n_init T 80 4\n__bss_start D 200 4\nexternal U\n' > "$work/good"
"$python" "$source_dir/bin/symbols-check.py" --nm "$work/nm" --lib "$work/good" --symbols-file "$work/api"
printf 'unrelated_export T 300 4\n' >> "$work/good"
status=0
"$python" "$source_dir/bin/symbols-check.py" --nm "$work/nm" --lib "$work/good" --symbols-file "$work/api" > "$work/extra.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep -q 'unknown symbol exported: unrelated_export' "$work/extra.log"
printf '_init T 80 4\n' > "$work/missing"
status=0
"$python" "$source_dir/bin/symbols-check.py" --nm "$work/nm" --lib "$work/missing" --symbols-file "$work/api" > "$work/missing.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep -q 'missing symbol: public_api' "$work/missing.log"
echo 'ELF bookkeeping accepted; extra/missing APIs rejected: PASS'

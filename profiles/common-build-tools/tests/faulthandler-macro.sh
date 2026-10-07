#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted extraction of CPython's production definitions.
# Compile upstream's array count with the retained platform macro adaptations.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: $0 PATCHED_PYTHON PRISTINE_PYTHON NEW_WORK" >&2; exit 2; }
patched=$1 pristine=$2
mkdir "$3"
work=$(CDPATH= cd -- "$3" && pwd)
cp "$patched/Include/pymacro.h" "$work/pymacro.h"
# Keep the actual record, signal typedefs and array; this fixture does not
# compile the rest of the extension or Python runtime internals.
grep '^typedef void (\*PyOS_sighandler_t)(int);$' \
    "$pristine/Include/pylifecycle.h" > "$work/signal-type.h"
awk '/^#ifdef HAVE_SIGACTION$/ { take=1 } take { print } \
    /^#endif.*HAVE_SIGACTION/ { exit }' \
    "$pristine/Include/internal/pycore_faulthandler.h" >> "$work/signal-type.h"
grep -q 'typedef struct sigaction _Py_sighandler_t;' "$work/signal-type.h"
awk '/^typedef struct \{/ { take=1 } take { print } /} fault_handler_t;/ { exit }' \
    "$pristine/Modules/faulthandler.c" > "$work/record.h"
awk '/^static fault_handler_t faulthandler_handlers\[\]/ { take=1 } take { print } \
    /Py_ARRAY_LENGTH\(faulthandler_handlers\);/ { exit }' \
    "$pristine/Modules/faulthandler.c" > "$work/handlers.h"
grep -q 'Py_ARRAY_LENGTH(faulthandler_handlers)' "$work/handlers.h"
for layout in sigaction signal; do
for absent in neither bus ill both; do
    name=$layout-$absent
    cat > "$work/$name.c" <<'C'
#include <stddef.h>
#include <stdint.h>
#include <signal.h>
/* The full header also declares unrelated public version-packing functions. */
#define PyAPI_FUNC(type) extern type
/* Exercise the recipe's NetBSD branch after the host system headers. */
#ifndef __NetBSD__
#define __NetBSD__ 1
#endif
#include "pymacro.h"
C
    if [ "$layout" = sigaction ]; then echo '#define HAVE_SIGACTION 1' >> "$work/$name.c"; else
        echo '#undef HAVE_SIGACTION' >> "$work/$name.c"
    fi
    cat "$work/signal-type.h" >> "$work/$name.c"
    case "$absent" in bus|both) echo '#undef SIGBUS' >> "$work/$name.c" ;; esac
    case "$absent" in ill|both) echo '#undef SIGILL' >> "$work/$name.c" ;; esac
    cat "$work/record.h" "$work/handlers.h" >> "$work/$name.c"
    cat >> "$work/$name.c" <<'C'
int
main(void)
{
    if (faulthandler_handlers[0].signum <= 0)
        return 2;
    return faulthandler_nsignals !=
        sizeof(faulthandler_handlers) / sizeof(faulthandler_handlers[0]);
}
C
    # Production records intentionally omit trailing zero-initialized fields.
    "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-missing-field-initializers \
        "$work/$name.c" -o "$work/$name" > "$work/$name.log" 2>&1
    "$work/$name"
    echo "PASS: actual NetBSD macro + handler initializer ($layout, $absent absent)"
done
done
cat > "$work/pointer.c" <<'C'
#include <stddef.h>
#include <stdint.h>
#define PyAPI_FUNC(type) extern type
#ifndef __NetBSD__
#define __NetBSD__ 1
#endif
#include "pymacro.h"
static int *pointer;
static const size_t count = Py_ARRAY_LENGTH(pointer);
int main(void) { return (int)count; }
C
if "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror "$work/pointer.c" \
    -o "$work/pointer" > "$work/pointer.log" 2>&1; then
    echo 'FAIL: Py_ARRAY_LENGTH accepted a pointer' >&2
    exit 1
fi
grep -Eq 'negative|array.*size|static assertion' "$work/pointer.log"
echo 'PASS: actual macro rejects pointer; this compiler only, not a native package gate'

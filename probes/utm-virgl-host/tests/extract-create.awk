# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted strict production function extraction.
# Select one top-level named function. Never substitute its implementation.
BEGIN { if (name == "") exit 2 }
{
    if ($0 ~ "^([a-zA-Z_][a-zA-Z_0-9 *]*[ *])?" name "\\(") {
        hits++
        if (hits != 1 || active) bad = 1
        active = 1
        start = FNR
        if ($0 ~ "^" name "\\(") print previous
    }
    if (active) {
        print
        code = $0
        gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
        opens = gsub(/\{/, "{", code)
        closes = gsub(/\}/, "}", code)
        depth += opens - closes
        if (opens) body = 1
        if (body && depth == 0) { active = 0; complete++; finish = FNR }
    }
    previous = $0
}
END {
    if (hits != 1 || active || complete != 1 || bad) {
        print "Unexpected CREATE extraction shape: " name > "/dev/stderr"
        exit 1
    }
    if (rangefile != "") print name, start, finish > rangefile
}

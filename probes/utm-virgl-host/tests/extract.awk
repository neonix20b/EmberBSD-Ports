# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted extraction of actual pinned renderer functions.
# Preserve the original renderer license header with the extracted source.
NR == 1 { license = 1 }
license { print; if ($0 ~ /^ \*+\//) license = 0; next }
/^static uint64_t vrend_transfer_size\(/ || /^static bool check_iov_bounds\(/ {
    found++; active = 1
    print "#line " NR " \"" FILENAME "\""
}
active {
    print
    line = $0
    opens = gsub(/\{/, "{", line)
    closes = gsub(/\}/, "}", line)
    depth += opens - closes
    if (opens) opened = 1
    if (opened && depth == 0) { active = 0; opened = 0 }
}
END {
    if (found != 2 || depth || active || license) {
        print "Unexpected renderer extraction shape" > "/dev/stderr"
        exit 1
    }
}

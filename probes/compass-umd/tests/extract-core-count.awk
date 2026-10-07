# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted extraction of pinned production text.
BEGIN {
    print "// Copyright (C) 2023-2025 Arm Technology (China) Co. Ltd."
    if (mode == "capability")
        print "// SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note"
    else
        print "// SPDX-License-Identifier: Apache-2.0"
    if (mode != "getter" && mode != "members" && mode != "capability") exit 1
}
function start() {
    found++
    active = 1
    print "#line " NR " \"" FILENAME "\""
}
mode == "members" && /^  (std::vector<aipu_partition_cap> m_part_caps;|uint32_t m_(partition|cluster|core)_cnt =)/ {
    print
    found++
    key = $0
    sub(/ =.*|;.*/, "", key)
    sub(/^.* /, "", key)
    seen[key]++
}
mode == "getter" && /^  aipu_ll_status_t get_core_count\(/ { start() }
mode == "capability" && /^struct aipu_(partition_cap|cap) \{/ { seen[$2]++; start() }
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
    expected = mode == "members" ? 4 : (mode == "capability" ? 2 : 1)
    bad = mode == "members" && (seen["m_part_caps"] != 1 ||
        seen["m_partition_cnt"] != 1 || seen["m_cluster_cnt"] != 1 || seen["m_core_cnt"] != 1)
    bad = bad || (mode == "capability" && (seen["aipu_partition_cap"] != 1 || seen["aipu_cap"] != 1))
    if (active || depth || found != expected || bad) {
        print "Unexpected production extraction shape: " mode > "/dev/stderr"
        exit 1
    }
}

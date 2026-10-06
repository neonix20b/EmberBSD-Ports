# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted. Extract exact production text; no method copies.
# Each selector must match once in the pinned original or patched input.
BEGIN {
    print "// Copyright (C) 2023-2025 Arm Technology (China) Co. Ltd."
    print "// SPDX-License-Identifier: Apache-2.0"
}
function start() {
    found++
    active = 1
    print "#line " NR " \"" FILENAME "\""
}
mode == "members" && /^  (int m_fd =|std::atomic<bool> m_tick_counter =)/ { print; found++ }
mode == "status" && /^typedef enum \{/ { start() }
mode == "status" && active { print; if (/^} aipu_ll_status_t;/) active = 0; next }
mode == "lifetime" && /^Aipu::Aipu\(\)|^Aipu::~Aipu\(\)|^aipu_ll_status_t Aipu::init\(\)|^void Aipu::deinit\(\)/ { start() }
mode == "factory" && /^  static (aipu_ll_status_t get_aipu|bool put_aipu)\(/ { start() }
mode == "tick" && /^  case AIPU_IOCTL_DISABLE_TICKCOUNTER: \{/ { start() }
active && mode != "status" {
    print
    line = $0
    opens = gsub(/\{/, "{", line)
    closes = gsub(/\}/, "}", line)
    depth += opens - closes
    if (depth == 0) active = 0
}
END {
    expected = (mode == "members" || mode == "factory") ? 2 : (mode == "lifetime" ? 4 : 1)
    if (active || depth || found != expected) {
        print "Unexpected production extraction shape: " mode > "/dev/stderr"
        exit 1
    }
}

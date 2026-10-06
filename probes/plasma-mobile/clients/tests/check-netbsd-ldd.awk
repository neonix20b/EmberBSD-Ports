# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 EmberBSD contributors. AI-assisted contract probe.
/not found/ { missing = 1 }
/stdc\+\+/ {
    runtimes++
    if ($1 == "-lstdc++.9" && $2 == "=>" && $3 == "/usr/lib/libstdc++.so.9") {
        expected++
    }
}
END { exit !(runtimes == 1 && expected == 1 && !missing) }

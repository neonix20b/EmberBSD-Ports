# SPDX-License-Identifier: BSD-2-Clause
# NetBSD ldd contract: selected input library, one C++ runtime, no missing DSO.
/not found/ { missing = 1 }
/stdc\+\+/ { runtimes++ }
$1 ~ /^-linput[.]/ {
    inputs++
    if ($2 == "=>" && index($3, expected) == 1) selected++
}
END { exit !(inputs == 1 && selected == 1 && runtimes == 1 && !missing) }

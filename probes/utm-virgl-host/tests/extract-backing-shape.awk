# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted complete named production struct/enum extraction.
$0 == kind " " name " {" { active=1;hits++ }
active {print;if(/^};/){active=0;done++}}
END {if(hits!=1 || active || done!=1){print "Unexpected source shape: " name > "/dev/stderr";exit 1}}

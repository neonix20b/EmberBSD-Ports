# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted complete overlay hunk/CREATE non-overlap audit.
# First input: exact original CREATE declaration/body line ranges. Second:
# complete original UTM overlay. Track preceding deltas per sequential diff.
FNR == NR { names[++ranges]=$1; start[$1]=$2; finish[$1]=$3; next }
/^diff --git / {
    if (relevant) for(i=1;i<=ranges;i++) {n=names[i];start[n]+=delta[n];finish[n]+=delta[n];delta[n]=0}
    relevant=($3=="a/hw/display/virtio-gpu-virgl.c")
    if(relevant) sections++
}
relevant && /^@@/ {
    field=$2;sub(/^-/,"",field);split(field,old,",");oldstart=old[1]+0;oldcount=(old[2]==""?1:old[2]+0)
    field=$3;sub(/^\+/,"",field);split(field,new,",");newcount=(new[2]==""?1:new[2]+0)
    for(i=1;i<=ranges;i++) {
        n=names[i]
        if ((oldcount && oldstart<=finish[n] && oldstart+oldcount>start[n]) || (!oldcount && oldstart>=start[n] && oldstart<finish[n])) {
            print "Overlay hunk overlaps CREATE: " n > "/dev/stderr"; bad=1
        }
        if(oldstart<start[n]) delta[n]+=newcount-oldcount
    }
}
END {
    if(ranges!=2 || sections!=3 || bad) {print "Unexpected overlay CREATE audit shape" > "/dev/stderr";exit 1}
    print "PASS: complete pinned overlay has no hunk overlap with either CREATE function"
}

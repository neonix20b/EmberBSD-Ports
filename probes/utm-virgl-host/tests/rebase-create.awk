# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD, AI-assisted exact CREATE hunk-coordinate adaptation.
# Mechanical hunk location adaptation: unique exact whole old hunk required.
NR==FNR {src[FNR]=$0; total=FNR;next}
function emit( i,j,k,n,oldn,newn,place,hits,parts,pos) {
 if(!hunk)return
 oldn=0;newn=0
 for(i=1;i<=nlines;i++){k=substr(lines[i],1,1);if(k==" "||k=="-")old[++oldn]=substr(lines[i],2);if(k==" "||k=="+")newn++}
 hits=0
 for(i=1;i<=total-oldn+1;i++){for(j=1;j<=oldn;j++)if(src[i+j-1]!=old[j])break;if(j>oldn){place=i;hits++}}
 if(hits!=1){print "Non-unique/inapplicable complete hunk" > "/dev/stderr";exit 1}
 printf "@@ -%d,%d +%d,%d @@%s\n",place,oldn,place+delta,newn,tail
 for(i=1;i<=nlines;i++)print lines[i]
 delta+=newn-oldn;delete lines;delete old;nlines=0
}
/^@@ / {emit();hunk=1;tail=$0;sub(/^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/,"",tail);next}
{if(hunk)lines[++nlines]=$0;else print}
END {emit()}

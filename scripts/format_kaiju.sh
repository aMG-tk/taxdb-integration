#!/bin/bash

TAXID=$1
ACC2TAXID=$2
FAA=$3

# awk magic thanks @https://www.biostars.org/p/227046/
echo ${TAXID} | grep -F -f - ${ACC2TAXID} | cut -f1 | grep -w -A1 -F -f - ${FAA} | sed '/^--$/d' | sed "/^>/c \>${TAXID}" | awk 'BEGIN{RS=">"}{if(NR>1)print ">"(NR-1)"_"$1"\n"$2}' | tr 'BZ' 'DE' | sed '/^>/! s/[^ARNDCQEGHILKMFPSTWYV]//g'

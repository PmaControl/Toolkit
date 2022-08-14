#!/bin/bash


REGEX=""



    NEW_STRING="#!/bin/bash

set -e


include lib/6t-progress-bar
include lib/6t-gg

TOTAL=$(sed 's:#.*$::g' $0 | grep progressbar | wc -l)
#TOTAL=$((TOTAL-1))

spinner 
progressbar 
"



    #echo -ne "$NEW_STRING";





while IFS= read -r line; do
    if [[ "$line" =~ ^include[[:space:]]([a-z0-9/-]+*)$ ]]; then 
        #echo "--->${BASH_REMATCH[1]}"

        file="${BASH_REMATCH[1]}.sh"
        if [[ -f "$file" ]]; then
            TOTAL=$(sed 's:#.*$::g' ${BASH_REMATCH[1]}.sh)
            echo -n "$TOTAL"
        else
            echo ""
            echo "Unknow file : $file"
            exit 4
        fi
    else
        echo $line
    fi
done <<< "$NEW_STRING"

  


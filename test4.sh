#!/bin/bash
str='foo = 1
bar = 2
boo = 3
'
re='bar = ([^\
]*)'
if [[ "$str" =~ $re ]]; then
        echo "${BASH_REMATCH[1]}"
else
        echo no match
fi

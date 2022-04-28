#!/bin/bash

# Module: lib/debug

# Author: Aurélien LEQUOY
# Email:  aurelien@68koncept.com

function 6t-join-by { 
    local d=$1;
    shift;
    local f=$1;
    shift;
    printf %s "$f" "${@/#/$d}";
}
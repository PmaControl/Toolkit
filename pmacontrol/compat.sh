#!/bin/bash


compat()
{
    local file_distrib="distrib/$OPERATING_SYSTEM.sh"

    if [[ -f "$file_distrib" ]]
    then
        display "Operating system supported : '$OPERATING_SYSTEM'"

        # shellcheck=SC1090
        source "$PATH_PMA/$file_distrib"

        #suite des command ici
    else
        display "[ERROR] This operating system is not supported : '$OPERATING_SYSTEM'"
        exit 1;
    fi
}
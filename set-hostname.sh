#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

HOSTNAME=$(hostname)
NEWHOSTNAME=""
VERSION="1.1"
DATE=$(stat -c '%y' $0 | cut -d ' ' -f 1)
VERBOSE=0
file_name=$(basename $(test -L "$0" && readlink "$0" || echo "$0"))

while getopts 'uh:vV' flag; do
  case "${flag}" in
    u)
        echo "Change hostname to a new one"
        echo "example : ./hostname -h 'new-hostname'"
        echo " "
        echo "options:"
        echo "-u              Display this help"
        echo "-h              Set the new hostname for the current machine"
	echo "-v              Verbose mode"
        echo "-V              Display the version of this tool"
	exit 0
    ;;

    V)
	    echo "${file_name} ver ${VERSION} (${DATE})"
	    exit 0
    ;;

    h) NEWHOSTNAME="${OPTARG}";;

    v) VERBOSE=1;;
    *) echo "Unexpected option ${flag}"
	exit 1
    ;;
  esac
done

if [[ "$#" -eq 0 ]]; then
    echo "Illegal number of parameters"
    echo "For usage ./${file_name} -u"
    exit 1;
fi

#test if name is a valid hostname
#res=$(echo "${NEWHOSTNAME}" | grep -E '^[a-z0-9][a-z0-9-]+$')
#if [[ -z ${res} ]]; then
#    echo "Error"
#fi

if [[ ${VERBOSE} -eq 1 ]]; then
	echo "hostname : '${HOSTNAME}' will be switch by '${NEWHOSTNAME}'"
fi

# for all
sed "s/${HOSTNAME}/${NEWHOSTNAME}/g" -i /etc/hosts

# old fashion
hostname "${NEWHOSTNAME}"
echo "${NEWHOSTNAME}" > /etc/hostname

# new fashion
hostnamectl set-hostname "${NEWHOSTNAME}"

# to take effect immediatly in shell
bash

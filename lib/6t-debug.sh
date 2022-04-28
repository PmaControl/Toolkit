#!/bin/bash

# Module: lib/debug

# Author: Aurélien LEQUOY
# Email:  aurelien@68koncept.com

function debug()
{
	if [[ ${DEBUG} == true ]]; then
		tmp_var=$1
		date=$(date +"%F %H:%M:%S")
		echo "[${date}][DEBUG] ${tmp_var}"
	fi
}

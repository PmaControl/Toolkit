#!/bin/bash

# Module: lib/dns

# Author: Aurélien LEQUOY
# Email:  aurelien@68koncept.com

resolvedIP=$(nslookup "$1" | awk -F':' '/^Address: / { matched = 1 } matched { print $2}' | xargs)

# Deciding the lookup status by checking the variable has a valid IP string

[[ -z "$resolvedIP" ]] && echo "$1" lookup failure || echo "$1" resolved to "$resolvedIP"
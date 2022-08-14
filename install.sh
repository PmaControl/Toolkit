#!/bin/bash

set -e
source lib/6t-include.sh

include lib/6t-progress-bar


TOTAL=$(sed 's:#.*$::g' $0 | grep progressbar | wc -l)
TOTAL=$((TOTAL-1))

spinner "sleep 1" "sleep 1"
progressbar "${TOTAL}"


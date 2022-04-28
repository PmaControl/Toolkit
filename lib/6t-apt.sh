#!/bin/bash

# Module: lib/6t-apt

# Author: Aurélien LEQUOY
# Email:  aurelien@68koncept.com
function 6t-apt()
{
    REQUIRED_PKG=$1
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' "${REQUIRED_PKG}"|grep "install ok installed")
    echo Checking for "${REQUIRED_PKG}": "${PKG_OK}"
    if [[ "" = "$PKG_OK" ]]; then
    echo "No ${REQUIRED_PKG}. Setting up ${REQUIRED_PKG}."
    apt-get --yes install "${REQUIRED_PKG}"
    fi
}
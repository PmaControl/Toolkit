#!/bin/bash

# first param : SERVER (localhost if none) Else IP
# second param : INSTALL / REMOVE / PURGE
# third param : Package name

REQUIRED_PKG=''
HOST='127.0.0.1'
MODE='install'
DEBUG=0
ERROR_LOG='/tmp/log'

while getopts 'hs:m:p:l:e:d' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./apt.sh -s 10.38.68.100 -p mariadb-client -m install"
        echo " "
        echo "options:"
	echo "-s	server (DNS / IP), install in local else"
        echo "-m        mode (install / remove / purge"
        echo "-p        package name"
	echo "-l	log file"
	echo "-e	error log"
	echo "-d	debug mode"
        exit 0
    ;;
    p) REQUIRED_PKG="${OPTARG}" ;;
    s) HOST="${OPTARG}" ;;
    m) MODE="${OPTARG}" ;;
    d) DEBUG=1 ;;
    *) echo "Unexpected option ${flag}" 
        exit 0
    ;;
  esac
done


if [[ ${DEBUG} = 1 ]]
then
	echo "# [debug] REQUIRED_PKG	= ${REQUIRED_PKG}"
	echo "# [debug] SERVER		= ${HOST}"
	echo "# [debug] MODE		= ${MODE}"
fi


function display() {
	#echo "Parameter #1 is $1"
	msg=$1
	date=$(date '+%Y-%M-%d %H:%M:%S')
	echo -e "\e[1;35m[${date}]\e[0m \e[37m${HOST}:\e[0m ${msg}"
}


COLORED_PKG="\e[1;95m${REQUIRED_PKG}\e[0m"
#REQUIRED_PKG="mariadb-client"


case "${MODE}" in
    install)


PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2> ${ERROR_LOG} |grep "install ok installed")
#echo "Checking for ${REQUIRED_PKG}: ${PKG_OK}"
display "Checking for ${COLORED_PKG}: ${PKG_OK}"
if [ "" = "$PKG_OK" ]; then
  display "No $COLORED_PKG. Setting up $COLORED_PKG."
  apt-get --yes install $REQUIRED_PKG 2>&1 >> /tmp/log  
  #KO or success
	display "${COLORED_PKG} installed."
else
	display "${COLORED_PKG} already installed."
fi

    ;;
    remove) 

PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
display "Checking for ${COLORED_PKG}: ${PKG_OK}"

if [ "" = "$PKG_OK" ]; then
	display "No $COLORED_PKG found. Nothing to do."
else
	display "Removing ${COLORED_PKG}."
	apt-get --yes remove $REQUIRED_PKG 2>&1 >> /tmp/log
fi

 ;;
 
    *) echo "Unexpected option ${flag}" 
        exit 0
    ;;
esac





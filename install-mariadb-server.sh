#!/bin/bash
set +x
set -euo pipefail

while getopts 'hm:p:u:P:s:U:' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./install-proxysql.sh -s '10.68.68.179' -p '10.68.68.179,10.68.68.180' -o '10.114.5.13'"
        echo " "
        echo "options:"

        echo "-m ip1,ip2,ip3          specify the list of mysql server coma separated"
        echo "-u                      specify user for MySQL (dba account)"
        echo "-p                      specify password for MySQL (dba )"
        echo "-U                      specify user for SSH (default ROOT)"
        echo "-s                      server to install"
        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    u) DBA_USER="${OPTARG}" ;;
    p) DBA_PASSWORD="${OPTARG}" ;;
    U) SSH_USER="${OPTARG}"   ;;
    s) SERVER_TO_INSTALL="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

function getProxy()
{
  cat /etc/apt/apt.conf.d/* | { grep -E 'Acquire::https::proxy' | grep -Eo 'https?://.*([0-9]+|/)' || true;}
}


if [[ -n "${SERVER_TO_INSTALL}" ]]
then

  HTTP_PROXY=''
  HTTP_PROXY=$(getProxy)
  
  export http_proxy=${HTTP_PROXY}
  export https_proxy=${HTTP_PROXY}

  who=$(whoami)

  sudo=''
  if [[ "${who}" != "root" ]]
  then
    echo "Passage avec SUDO"
    
    sudo="sudo http_proxy=${HTTP_PROXY} https_proxy=${HTTP_PROXY}"
  fi

  echo "#################################################"
  echo "HTTP_PROXY : '${HTTP_PROXY}'"
  echo "#################################################"
  echo "WHOAMI : ${who}"
  echo "#########################################"
  echo "apt update"
  echo "#########################################"

  $sudo apt update

  echo "#########################################"
  echo "apt upgrade"
  echo "#########################################"

  $sudo apt -y upgrade

  echo "#########################################"
  echo "apt install ..."
  echo "#########################################"

  $sudo apt install -y fdisk
  $sudo apt install -y git
  $sudo apt install -y tig
  $sudo apt install -y wget
  $sudo apt install -y ntp
  $sudo apt install -y gdisk
  
  $sudo service ntp restart
  
  #$sudo apt install -y tee

  echo "GPT"
  printf 'n\n\n\n\n\nw\ny\n' | $sudo gdisk /dev/sdb
  $sudo mkfs.ext4 /dev/sdb1

  $sudo blkid /dev/sdb1

  blkid=$($sudo blkid /dev/sdb1 | cut -f 2 -d '=' | cut -f1 -d ' ')

  echo "UUID=${blkid} /srv        ext4    rw,noatime,nodiratime,nobarrier,data=ordered 0 0" | $sudo tee -a /etc/fstab

  $sudo mount -a

  cd /srv
  $sudo mkdir -p code
  cd code

  echo "PROXY : '${HTTP_PROXY}'"

  $sudo git config --global http.proxy "${HTTP_PROXY}"
  $sudo git clone https://github.com/PmaControl/Toolkit.git toolkit
  cd toolkit

  pass=$($sudo openssl rand -base64 32)

  $sudo ./install-mariadb.sh -v 10.7 -p "$pass" -d /srv/mysql
  $sudo mysql --defaults-file=/root/.my.cnf -e "GRANT ALL ON *.* to '${DBA_USER}'@'%' IDENTIFIED BY '${DBA_PASSWORD}' WITH GRANT OPTION;"

else
    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    for mariadb in "${MARIADB_SERVER[@]}"; do

        echo "######################################################"
        echo "# Connect to ${mariadb}"
        echo "######################################################"
        
        cat "$0" | ssh ${SSH_USER}@${mariadb} MARIADB_SERVERS=${MARIADB_SERVERS} SERVER_TO_INSTALL=${mariadb} DBA_USER=${DBA_USER} DBA_PASSWORD=${DBA_PASSWORD} '/bin/bash'
    done
fi

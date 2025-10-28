#!/bin/bash
set +x
set -euo pipefail

while getopts 'hm:p:u:P:s:U:' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./install-proxysql.sh -s '10.68.68.179' -m '10.68.68.179,10.68.68.180' -o '10.114.5.13'"
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

function isDevMounted () { findmnt --source "$1" >/dev/null;}


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
  echo "apt install NTP"
  echo "#########################################"
  $sudo apt install -y ntp

  $sudo service ntp stop
  $sudo ntpd -gq
  $sudo service ntp start


  sleep 1
  $sudo apt update

  echo "#########################################"
  echo "apt upgrade"
  echo "#########################################"

  $sudo apt -y upgrade

  echo "#########################################"
  echo "apt install ..."
  echo "#########################################"

  #$sudo apt install -y fdisk
  $sudo apt install -y git
  $sudo apt install -y tig
  $sudo apt install -y wget
  $sudo apt install -y gdisk
  $sudo apt install -y btop
  
  #$sudo apt install -y tee

  DEVTARGET='/dev/sdb1'

  if  isDevMounted "${DEVTARGET}";
  then 
        echo "#########################"
        echo "device is mounted"
        echo "#########################"
        df -h
  else 
        echo "GPT ---------------------------->"
        TRI=${DEVTARGET::-1}
        printf 'n\n\n\n\n\nw\ny\n' | $sudo gdisk "${TRI}"
        $sudo mkfs.ext4 "${DEVTARGET}"
        $sudo blkid "${DEVTARGET}"
        blkid=$($sudo blkid "${DEVTARGET}" | cut -f 2 -d '=' | cut -f1 -d ' ')
        echo "UUID=${blkid} /srv        ext4    rw,noatime,nodiratime,nobarrier,data=ordered 0 0" | $sudo tee -a /etc/fstab
        $sudo mount -a
  fi

  cd /srv
  $sudo mkdir -p code
  cd code

  echo "PROXY : '${HTTP_PROXY}'"

  #$sudo git config --global http.proxy "${HTTP_PROXY}"
  #$sudo git clone https://github.com/PmaControl/Toolkit.git toolkit
  #cd toolkit



REPO_URL="https://github.com/PmaControl/Toolkit.git"
TARGET_DIR="toolkit"

# === Clonage idempotent ===
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 Le dépôt existe déjà — mise à jour..."
  cd "$TARGET_DIR"

  # Récupérer la branche par défaut du remote
  DEFAULT_BRANCH=$(sudo git remote show origin | awk '/HEAD branch/ {print $NF}')

  sudo git fetch --all --quiet
  sudo git reset --hard "origin/${DEFAULT_BRANCH}" --quiet
else
  echo "⬇️  Clonage du dépôt..."
  sudo git clone "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

echo "✅ Répertoire prêt : $(pwd)"


pwgen() {
  local pass
  pass=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!@#$%^&*()-_=+?~' | head -c 32)
  # Vérifie les conditions et relance si non respectées
  while ! [[ "$pass" =~ [A-Z] && "$pass" =~ [a-z] && "$pass" =~ [0-9] && "$pass" =~ [\!\@\#\$\%\^\&\*\(\)\-\_\=\+\?\~] ]]; do
    pass=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!@#$%^&*()-_=+?~' | head -c 32)
  done
  echo "$pass"
}

  pass=$(pwgen)

  $sudo ./install-mariadb.sh -v 11.4 -p "${pass}" -d /srv/mysql -r
  $sudo mysql --defaults-file=/root/.my.cnf -e "GRANT ALL ON *.* to '${DBA_USER}'@'%' IDENTIFIED BY '${DBA_PASSWORD}' WITH GRANT OPTION;"

else
    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    for mariadb in "${MARIADB_SERVER[@]}"; do

        echo "######################################################"
        echo "# Connect to ${mariadb}"
        echo "######################################################"
        
        cat "$0" | ssh ${SSH_USER}@${mariadb} MARIADB_SERVERS="${MARIADB_SERVERS}" SERVER_TO_INSTALL="${mariadb}" DBA_USER="${DBA_USER}" DBA_PASSWORD="${DBA_PASSWORD}" '/bin/bash'
    done
fi

#!/bin/bash

set -eu



while getopts 'hm:p:u:P:v:U:' flag; do
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
        echo "-v                      version of mariadb"
        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    u) DBA_USER="${OPTARG}" ;;
    p) DBA_PASSWORD="${OPTARG}" ;;
    U) SSH_USER="${OPTARG}"   ;;
    s) SERVER_TO_INSTALL="${OPTARG}" ;;
    v) VERSION_MARIADB="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done


#############################



function cleanup()
{
  exit 1
}

function ctrl_c() {
  echo ""
  echo -ne "*** Trapped CTRL-C ***\\033[K\n"
  echo -ne "\\r...........................................................................[ ${COLOR_ERROR}✘${NC} ]${CLEAR_LINE}"
  diplay_log
  exit 1
}

spinner()
{
    trap ctrl_c INT

    local MSG=$1
    COMMAND=$2
    local COLOR_DATE='\033[0;35m'
    local COLOR_ERROR='\033[0;31m'
    local COLOR_SUCCESS='\033[0;32m'
    local COLOR_SECONDS='\033[0;33m'
    local BOLD=''
    local NORMAL=''
    local NC='\033[0m'
    local FRAME=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local FRAME_INTERVAL=0.1
    local CLEAR_LINE="\\033[K"

    LOG_GENERAL=$(mktemp)
    LOG_ERROR=$(mktemp)
    ERROR_CODE=$(mktemp)

    ($2 > ${LOG_GENERAL} 2> ${LOG_ERROR} ; echo $? > ${ERROR_CODE}) &
    pid=$!


    date=$(date '+%Y-%m-%d %H:%M:%S')
    START=$SECONDS
    #sleep $FRAME_INTERVAL

    modulo=${#FRAME[@]}

    i=0
    while ps -p $pid &>/dev/null; do
      #echo -ne "\\r[                 ] ${MSG} ..."

      item=$(($i % ${modulo}))

     # for k in "${!FRAME[@]}"; do
        OFFEST=$((SECONDS-START))
        echo -ne "\\r...........................................................................${BOLD}[ ${FRAME[item]} ]${NC}${CLEAR_LINE}"
        echo -ne "\\r${BOLD}[                 ] ${MSG} ...${NORMAL}"
        echo -ne "\\r${BOLD}[ ${COLOR_SECONDS}$OFFEST sec${NORMAL}"
        sleep $FRAME_INTERVAL
     # done

      i=$((i+1))
    done

    error_code=$(cat ${ERROR_CODE})
  
    if [[ "${error_code}" -eq 0 ]]; then

      if [[ -z "${error_code}" ]]; then
        diplay_log
        exit 1
      fi
      echo -ne "\\r...........................................................................[ ${COLOR_SUCCESS}✔${NC} ]${CLEAR_LINE}"
      echo -ne "\\r${COLOR_DATE}${date}${NC} ${MSG} \\n"
      #diplay_log
    else
      echo -ne "\\r...........................................................................[ ${COLOR_ERROR}✘${NC} ]${CLEAR_LINE}"
      diplay_log
      exit 1
    fi

    trap cleanup INT
}

diplay_log()
{
  error_code=$(cat ${ERROR_CODE})
  error=$(cat ${LOG_ERROR})
  log=$(cat ${LOG_GENERAL})
  local underline="\033[4m"
  local reset="\033[0m"
  local dim="\e[2m"

  running='(not running)'
  if ps -p ${pid} > /dev/null
  then
    running='(currently running...)'
  fi

  
  echo -ne "\\r${BOLD}[                 ] ${MSG} ${NORMAL}"
  echo -ne "\\r${COLOR_DATE}${date}${NC}\\n"
  echo ""
  echo ""
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}command   :${reset}${NORMAL} ${COMMAND}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}pid       :${reset}${NORMAL} ${pid} ${running}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}error     :${reset}${NORMAL} ${error_code}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}log error :${reset}${NORMAL}\n${dim}${error}${reset}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}log       :${reset}${NORMAL}\n${dim}${log}${reset}\n"
  echo "--------------------------------------------------------------------------------"
}

progressbar()
{
  local BAR_SIZE="######################################################"
  local MAX_BAR_SIZE="${#BAR_SIZE}"
  local CLEAR_LINE="\\033[K"

  #pour eviter un double affichage de la bare en cas de commande très rapide
  echo -ne "${CLEAR_LINE}"

  MAX_STEPS=$1

  set +u
  if [[ -n "${STEP}" ]]; then
    STEP=$((STEP+1))
  else
    STEP=1
  fi
  set -u

  # pour eviter les bug d'affichage en cas d'erreur utilisateur
  if [[ $STEP -gt $MAX_STEPS ]]; then
    MAX_STEPS=${STEP}
  fi
  
  perc=$(((STEP) * 100 / MAX_STEPS))
  percBar=$((perc * MAX_BAR_SIZE / 100))
  
  if [[ ${STEP} -ne ${MAX_STEPS} ]] ; then
    echo ""
  fi

  size=${BAR_SIZE//#/ }
  echo -ne "Install (${STEP}/${MAX_STEPS}) [${size}] $perc %${CLEAR_LINE}"
  echo -ne "\rInstall (${STEP}/${MAX_STEPS}) [${BAR_SIZE:0:percBar}\n"

  if [[ ${STEP} -ne ${MAX_STEPS} ]]
  then
    echo -ne "\033[2A"
  fi
}




#############################

function getProxy()
{
    cat /etc/apt/apt.conf.d/* | { grep -E 'Acquire::https::proxy' | grep -Eo 'https?://.*([0-9]+|/)' || true;}
}

function isDevMounted () { findmnt --source "$1" >/dev/null;}


function setProxy()
{
    HTTP_PROXY=''
    HTTP_PROXY=$(getProxy)

    export http_proxy=${HTTP_PROXY}
    export https_proxy=${HTTP_PROXY}
}

function setSudo()
{

    who=$(whoami)

    sudo=''
    if [[ "${who}" != "root" ]]
    then
    echo "Passage avec SUDO"

    sudo="sudo http_proxy=${HTTP_PROXY} https_proxy=${HTTP_PROXY}"
    fi

}


function setNtp()
{

    $sudo apt install -y ntp

    $sudo service ntp stop
    $sudo ntpd -gq
    $sudo service ntp start

}

function install()
{
  REQUIRED_PKG=$1
  PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG 2> /dev/null || echo "not installed" |grep "install ok installed")
  echo Checking for $REQUIRED_PKG: $PKG_OK
  if [ "" = "$PKG_OK" ]; then
    echo "No $REQUIRED_PKG. Setting up $REQUIRED_PKG."
    apt-get --yes install $REQUIRED_PKG
  fi
}

function mount_and_format()
{
  set -e
  TRI=${DEVTARGET::-1}

  if [ -e ${TRI} ]; then
    echo "Device exists";
  else
    echo "Device does not exist ($TRI)";
    exit 15
  fi

  if  isDevMounted "${DEVTARGET}";
  then
        echo "#########################"
        echo "device is mounted"
        echo "#########################"
        df -h
  else
        echo "GPT ---------------------------->"
        printf 'n\n\n\n\n\nw\ny\n' | $sudo gdisk "${TRI}"
        $sudo mkfs.ext4 "${DEVTARGET}"
        $sudo blkid "${DEVTARGET}"
        blkid=$($sudo blkid "${DEVTARGET}" | cut -f 2 -d '=' | cut -f1 -d ' ')
        echo "UUID=${blkid} /srv        ext4    rw,noatime,nodiratime,nobarrier,data=ordered 0 0" | $sudo tee -a /etc/fstab
        $sudo mount -a
  fi
}

install_toolkit()
{
  PROXY=$(getProxy)
  cd /srv/code
  $sudo git config --global http.proxy "${PROXY}"

  if [[ -e /srv/code/toolkit ]]
  then
    cd /srv/code/toolkit
    $sudo git pull
  else
    $sudo git clone https://github.com/PmaControl/Toolkit.git toolkit
  fi
}


add_repo()
{
    MARIADB=/etc/apt/sources.list.d/mariadb.list

	if [[ -f "$MARIADB" ]]
	then
        echo "Deleteing existing repositoriy : ${MARIADB}"
        # rm "$MARIADB"

    else

        curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-${VERSION}"
	fi
}


install_mariadb()
{


    debconf-set-selections <<< "mariadb-server-${VERSION} mysql-server/root_password password $1"
	debconf-set-selections <<< "mariadb-server-${VERSION} mysql-server/root_password_again password $1"

    install mariadb-server-$2

}



create_cnf()
{

    password_file='/root/.my.cnf'

    if [[ -f "$password_file" ]]
	then
        echo "/root/.my.cnf already exist"
    else
        echo -e "[client]
user=root
password='$1'" > "$password_file"
    fi
}

generate_id_server()
{
    ip=$(hostname -I)
    echo "IP : ${ip}"
    crc32=$(echo -n "${ip}" | gzip -c | tail -c8 | hexdump -n4 -e '"%u"')
    echo "crc32 : $crc32"
    id_server=$(echo -n "${crc32}" | cut -d ' ' -f 2 | tr -d '\n')
    echo "ID Server : ${id_server}"

    ID_SERVER=${id_server}
}

TOTAL=$(sed 's:#.*$::g' $0 | grep progressbar | wc -l)
TOTAL=$((TOTAL-1))

echo "TOTAL : $TOTAL"


spinner "set proxy if exist" "setProxy"
progressbar "${TOTAL}"

setSudo

#spinner "install and set NTP server" "setNtp"
#progressbar "${TOTAL}"


#spinner "apt-get update" "apt-get update"
#progressbar "${TOTAL}"


#spinner "apt-get dist-upgrade" "apt-get -y dist-upgrade"
#progressbar "${TOTAL}"



spinner "Install wget" "install wget"
progressbar "${TOTAL}"

spinner "Install gdisk" "install gdisk"
progressbar "${TOTAL}"


spinner "Install lsb-release" "install lsb-release"
progressbar "${TOTAL}"

spinner "Install gnupg2" "install gnupg2"
progressbar "${TOTAL}"

spinner "Install bc" "install bc"
progressbar "${TOTAL}"

spinner "Install curl" "install curl"
progressbar "${TOTAL}"

spinner "Install apt-transport-https" "install apt-transport-https"
progressbar "${TOTAL}"

spinner "Install ca-certificates" "install ca-certificates"
progressbar "${TOTAL}"

spinner "Install openssl" "install openssl"
progressbar "${TOTAL}"

DEVTARGET='/dev/sdb1'
#mount_and_format
#spinner "set GPT, format ext4 and mount ${DEVTARGET} to /srv" "mount_and_format"
#progressbar "${TOTAL}"

spinner "Add MariaDB repository" "add_repo"
progressbar "${TOTAL}"



#spinner "apt-get update" "apt-get update"
#progressbar "${TOTAL}"


password=$($sudo openssl rand -base64 32)
spinner "Install mariadb" "install_mariadb ${password} ${VERSION_MARIADB}"
progressbar "${TOTAL}"


spinner "Generate /root/.my.cnf" "create_cnf"
progressbar "${TOTAL}"

spinner "Generate server_id" "generate_id_server"
progressbar "${TOTAL}"

echo "server id : ${ID_SERVER}"

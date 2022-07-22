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
        echo "-a                      account for pmacontrol"

        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    u) DBA_USER="${OPTARG}" ;;
    p) DBA_PASSWORD="${OPTARG}" ;;
    U) SSH_USER="${OPTARG}"   ;;
    a) PMACONTROL_ACCOUNT ;;
    x) PROXYSQL_ACCOUNT ;;
    s) SERVER_TO_INSTALL="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

if [[ ! -z "${SERVER_TO_INSTALL}" ]]
then

  who=$(whoami)
  echo "~~~~~~~~~~~~~~~~ whoami : ${who}"
  
sudo=''
if [[ "${who}" != "root" ]]
then
	echo "Passage avec SUDO"
	
  sudo='sudo'
fi
	


  echo "############### whoami : ${who}"



  echo "#########################################"
  echo "apt update"
  echo "#########################################"

  set +e
  $sudo apt update
  set -e

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
  #$sudo apt install -y tee

  $sudo sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | $sudo fdisk /dev/sdb
    o # clear the in memory partition table
    n # new partition
    p # primary partition
    1 # partition number 1
      # default - start at beginning of disk 
      # default, extend partition to end of disk
    p # print the in-memory partition table
    w # write the partition table
    q # and we're done
EOF

  $sudo mkfs.ext4 /dev/sdb1

  $sudo blkid /dev/sdb1

  blkid=$($sudo blkid /dev/sdb1 | cut -f 2 -d '=' | cut -f1 -d ' ')

  #montage="UUID=${blkid} /srv        ext4    rw,noatime,nodiratime,nobarrier,data=ordered 0 0"
  echo "UUID=${blkid} /srv        ext4    rw,noatime,nodiratime,nobarrier,data=ordered 0 0" | $sudo tee -a /etc/fstab

  $sudo mount -a

  cd /srv
  $sudo mkdir code
  cd code
  $sudo git clone https://github.com/PmaControl/Toolkit.git toolkit
  cd toolkit

  pass=$($sudo openssl rand -base64 32)
  $sudo ./install-mariadb.sh -v 10.7 -p $pass -d /srv/mysql -a "pmacontrol:hhh"

  $sudo mysql --defaults-file=/root/.my.cnf -e "GRANT ALL ON *.* to ${DBA_USER}@'%' IDENTIFIED BY '${DBA_PASSWORD}' WITH GRANT OPTION;"

else
    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    
    for mariadb in "${MARIADB_SERVER[@]}"; do

        echo "######################################################"
        echo "# Connect to ${mariadb}"
        echo "######################################################"
        
        cat $0 | ssh ${SSH_USER}@${mariadb} MARIADB_SERVERS=${MARIADB_SERVERS} SERVER_TO_INSTALL=${mariadb} DBA_USER=${DBA_USER} DBA_PASSWORD=${DBA_PASSWORD} '/bin/bash'
        #ssh root@MachineB 'bash -s' < $0 $@ -s "${proxysql}"

        #pids[${mariadb}]=$!

    done

    #for pid in ${pids[*]}; do
    #  echo "Waiting ..."
    #  wait $pid
    #  date
    #  echo "END OF PID $pid"
    #done
fi

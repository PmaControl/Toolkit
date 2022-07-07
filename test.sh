#!/bin/bash


# reset all server
SERVERS='116,117,118,119,120'


IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do
    echo "qm rollback ${id_server} after_upgrade"
    ssh root@10.68.68.22 "qm rollback ${id_server} after_upgrade" 2>&1 
done


# reboot all server after roolback
MARIADB_SERVERS='10.68.68.183,10.68.68.186,10.68.68.187,10.68.68.179,10.68.68.182'
SSH_USER='root'

IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "reboot ${SSH_USER}@${mariadb}"
    ssh ${SSH_USER}@${mariadb} "reboot" 2>&1 
done


sleep 30


# full install
./install-cluster.sh -m '10.68.68.183,10.68.68.186,10.68.68.187' -p '10.68.68.179,10.68.68.182' -o '10.114.5.13' -u root

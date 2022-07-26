#!/bin/bash

# APT-UPGRADE


# reset all server
SERVERS='116,117,118,119,120'


IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do
    echo "qm rollback ${id_server} after_upgrade"
    ssh root@10.68.68.22 "qm rollback ${id_server} after_upgrade" 2>&1 
    echo "qm delsnapshot ${id_server} after_upgrade"
    ssh root@10.68.68.22 "qm delsnapshot ${id_server} after_upgrade" 2>&1 
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

IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "reboot ${SSH_USER}@${mariadb}"
    ssh ${SSH_USER}@${mariadb} "apt update" 2>&1 
    ssh ${SSH_USER}@${mariadb} "apt -y upgrade" 2>&1 
    ssh ${SSH_USER}@${mariadb} "apt -y dist-upgrade" 2>&1 
done

IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do
    echo "qm snapshot ${id_server} after_upgrade"
    
    ssh root@10.68.68.22 "qm snapshot ${id_server} after_upgrade" 2>&1 
done
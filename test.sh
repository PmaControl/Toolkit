#!/bin/bash


# reset all server
SERVERS='116,125,118,119,120'


IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do

    echo "qm stop ${id_server}"
    ssh root@10.68.68.22 "qm stop ${id_server}" 2>&1
    echo "qm rollback ${id_server} after_upgrade"
    ssh root@10.68.68.22 "qm rollback ${id_server} after_upgrade" 2>&1
    echo "qm start ${id_server}"
    ssh root@10.68.68.22 "qm start ${id_server}" 2>&1
done


## reboot all server after roolback
MARIADB_SERVERS='10.68.68.183,10.68.68.185,10.68.68.187,10.68.68.179,10.68.68.182'
SSH_USER='root'

echo "debut() du sleep 30"
sleep 20
echo "fin du sleep 30"


IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do

    echo "Reset server : ${mariadb}"
    #ssh-keygen -f "/root/.ssh/known_hosts" -R "${mariadb}"
    
    #echo "reboot ${SSH_USER}@${mariadb}"
    ssh ${SSH_USER}@${mariadb} "whoami" 2>&1 
done



# full install

#./install-cluster.sh -m '10.68.68.183' -p '10.68.68.179,10.68.68.182' -o '10.114.5.13' -u root
./install-cluster.sh -m '10.68.68.183,10.68.68.185,10.68.68.187' -p '10.68.68.179,10.68.68.182' -o '10.114.5.13' -u root -c 'Dalenys' -t cluster1_test

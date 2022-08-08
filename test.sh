#!/bin/bash


# reset all server
SERVERS='116,118,125,119,120'


IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do

    echo "qm stop ${id_server}"
    ssh root@10.68.68.22 "qm stop ${id_server}" 2>&1
    echo "qm rollback ${id_server} after_upgrade"
    ssh root@10.68.68.22 "qm rollback ${id_server} after_upgrade" 2>&1
    echo "qm start ${id_server}"
    ssh root@10.68.68.22 "qm start ${id_server}" 2>&1
done


echo "debut du sleep 30"
sleep 30
echo "fin du sleep 30"

# full install

./install-cluster.sh -m '10.68.68.183,10.68.68.185,10.68.68.187' -p '10.68.68.179,10.68.68.182' -o '10.114.5.13' -u root -c 'Dalenys' -t cluster1_test -e Test



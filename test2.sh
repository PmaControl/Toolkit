#!/bin/bash


# reset all server
SERVERS='116,117,118,119,120'


IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do
    echo "qm stop ${id_server}"
    ssh root@10.68.68.21 "qm stop ${id_server}" 2>&1
    echo "qm rollback ${id_server} after_upgrade"
    ssh root@10.68.68.21 "qm rollback ${id_server} after_upgrade" 2>&1
    echo "qm start ${id_server}"
    ssh root@10.68.68.21 "qm start ${id_server}" 2>&1
done


echo "debut du sleep 30"
sleep 30
echo "fin du sleep 30"


echo "start install ..."
# full install
./install-cluster.sh -m '10.68.68.231,10.68.68.180,10.68.68.101' -p '10.68.68.192,10.68.68.194' -o '10.114.5.13' -u root -c Dalenys -e Test -t cluster2

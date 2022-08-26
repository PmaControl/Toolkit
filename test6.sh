#!/bin/bash


# reset all server
SERVERS='200,201,202,203,204'
PROXMOX='10.99.68.64'
KEY='/root/.ssh/id_rsa'

IFS=',' read -ra SERVER <<< "$SERVERS"
for id_server in "${SERVER[@]}"; do
    echo "qm stop ${id_server}"
    ssh -i ${KEY} root@${PROXMOX} "qm stop ${id_server}" 2>&1
    echo "qm rollback ${id_server} after_upgrade"
    ssh -i ${KEY} root@${PROXMOX} "qm rollback ${id_server} after_upgrade" 2>&1
    echo "qm start ${id_server}"
    ssh -i ${KEY} root@${PROXMOX} "qm start ${id_server}" 2>&1
done


echo "debut du sleep 30"
sleep 30
echo "fin du sleep 30"


echo "start install ..."
# full install
./install-cluster.sh -m '10.99.68.74,10.99.68.75,10.99.68.76' -p '10.99.68.71,10.99.68.72' -o '10.99.68.73' -u root -c Proxmox -e Test -t cluster1

#!/bin/bash
set +x
set -euo pipefail

while getopts 'hm:p:o:t:a:u:' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./install-cluster.sh -m '10.114.5.14,10.114.5.15,10.114.5.16' -p '10.114.5.11,10.114.5.12' -o '10.114.5.13'"
        echo " "
        echo "options:"

        echo "-m ip1,ip2,ip3          specify the list of mysql server coma separated"
        echo "-p ip1,ip2              specify the list of proxysql server"
        echo "-o                      specify the list of mysql orchestrator"
        echo "-t                      type of topology (Master / Slave (MS) or Galera Cluster (GC)"
        echo "-a                      parameter for Pmacontrol"

        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    p) PROXYSQL_SERVERS="${OPTARG}" ;;
    o) MYSQL_ORCHESTRATOR_SERVER="${OPTARG}" ;;
    t) ARCHICTECTURE_TYPE="${OPTARG}" ;;
    a) PMACONTROL_PARAM="${OPTARG}";;
    u) SSH_USER="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

PMACONTROL_USER="pmacontrol"
PMACONTROL_PASSWORD=$(openssl rand -base64 32)

PROXYSQL_USER="proxysql"
PROXYSQL_PASSWORD=$(openssl rand -base64 32)

REPLICATION_USER="replication"
REPLICATION_PASSWORD=$(openssl rand -base64 32)

PROXYSQLADMIN_USER="proxysql"
PROXYSQLADMIN_PASSWORD=$(openssl rand -base64 32)

DBA_USER="dba"
DBA_PASSWORD=$(openssl rand -base64 32)


echo "#################################################"
echo "# PASSWORD GENERATION "
echo "#################################################"

echo ""
echo "#################################################"
echo "MySQL"
echo "#################################################"
echo "PmaControl  : ${PMACONTROL_USER} // ${PMACONTROL_PASSWORD}"
echo "ProxySQL    : ${PROXYSQL_USER} // ${PROXYSQL_PASSWORD}"
echo "Replication : ${REPLICATION_USER} // ${REPLICATION_PASSWORD}"
echo "DBA : ${DBA_USER} // ${DBA_PASSWORD}"

echo ""
echo "#################################################"
echo "ProxySQL Admin"
echo "#################################################"
echo "ProxySQL ADMIN : ${PROXYSQLADMIN_USER} // ${PROXYSQLADMIN_PASSWORD}"
echo ""
echo ""
echo ""

#test ssh connection all
IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
for proxysql in "${PROXYSQL_SERVER[@]}"; do
    echo "connect to ${SSH_USER}@${proxysql}"
    ssh ${SSH_USER}@${proxysql} "whoami" 2>&1 
done

IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "connect to ${SSH_USER}@${mariadb}"
    ssh ${SSH_USER}@${mariadb} "whoami" 2>&1 
done

echo "Install MariaDB Server"

./install-mariadb-server.sh -m '10.68.68.183,10.68.68.186,10.68.68.187' -U "${SSH_USER}" -s '' -u "${DBA_USER}" -p"${DBA_PASSWORD}"


IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "create user to ${SSH_USER}@${mariadb}"

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT ALL ON *.* to ${PMACONTROL_USER}@'%' IDENTIFIED BY '${PMACONTROL_PASSWORD}' WITH GRANT OPTION;"
    
    # boucle proxy

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT USAGE ON *.* to ${PROXYSQL_USER}@'%' IDENTIFIED BY '${PROXYSQL_PASSWORD}' WITH GRANT OPTION;"

    ip1=$(echo ${mariadb} | cut -f 1 -d ".")
    ip2=$(echo ${mariadb} | cut -f 2 -d ".")
    ip3=$(echo ${mariadb} | cut -f 3 -d ".")

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT REPLICATION CLIENT,REPLICATION SLAVE ON *.* to ${REPLICATION_USER}@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY '${REPLICATION_PASSWORD}' WITH GRANT OPTION;"
    

    # ssh ${SSH_USER}@${mariadb} "mysql -e " 2>&1 
done



./install-proxysql.sh -p "${PROXYSQL_SERVERS}" -m "${MARIADB_SERVERS}" -u ${PROXYSQL_USER} -P "${PROXYSQL_PASSWORD}" -s '' -U ${SSH_USER}


# TODO : take in consideration of all server are not in same /24
#ip1=$(hostname -I | cut -d' ' -f1 | cut -f 1 -d ".")
#ip2=$(hostname -I | cut -d' ' -f1 | cut -f 2 -d ".")
#ip3=$(hostname -I | cut -d' ' -f1 | cut -f 3 -d ".")

#mysql -e "GRANT REPLICATION CLIENT,REPLICATION SLAVE ON *.* to replication@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'10.82.131.5' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"

#CHANGE MASTER TO MASTER_HOST='10.112.5.14', MASTER_USER='replication', MASTER_PASSWORD='d937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI', MASTER_LOG_FILE='mariadb-bin.000001', MASTER_LOG_POS=923;

#mysql -e "GRANT USAGE ON *.* TO proxysql@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'UIlvRolnc1RYzLZweB4kEZGthhSyd9A6oEs1sTKZ39Y';"
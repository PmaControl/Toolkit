#!/bin/bash
set +x
set -euo pipefail

tmp_file=$(mktemp)
error_mysql=$(mktemp)
DEBUG="true"

path=${BASH_SOURCE%/*}
source $path/lib/6t-mysql-client.sh
source $path/lib/6t-debug.sh


while getopts 'hm:p:o:t:a:u:s:c:e:' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./install-cluster.sh -m '10.114.5.14,10.114.5.15,10.114.5.16' -p '10.114.5.11,10.114.5.12' -o '10.114.5.13' -s 'serversource'"
        echo " "
        echo "options:"

        echo "-m ip1,ip2,ip3          specify the list of mysql server coma separated"
        echo "-p ip1,ip2              specify the list of proxysql server"
        echo "-o                      specify the list of mysql orchestrator"
        echo "-t                      tags"
        echo "-a                      parameter for Pmacontrol"
        echo "-s                      server source"
        echo "-c                      client"
        echo "-e                      environment"

        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    p) PROXYSQL_SERVERS="${OPTARG}" ;;
    o) MYSQL_ORCHESTRATOR_SERVER="${OPTARG}" ;;
    t) TAG="${OPTARG}" ;;
    a) PMACONTROL_PARAM="${OPTARG}";;
    u) SSH_USER="${OPTARG}" ;;
    s) SERVER_SOURCE="${OPTARG}" ;;
    c) CLIENT="${OPTARG}" ;;
    e) ENVIRONMENT="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

PMACONTROL_USER="pmacontrol"
PMACONTROL_PASSWORD=$(openssl rand -base64 32)

PROXYSQL_USER="monitor"
PROXYSQL_PASSWORD=$(openssl rand -base64 32)

REPLICATION_USER="replication_slave"
REPLICATION_PASSWORD=$(openssl rand -base64 32)

PROXYSQLADMIN_USER="proxysql"
PROXYSQLADMIN_PASSWORD=$(openssl rand -base64 32)

MONITOR_USER="monitor"
MONITOR_PASSWORD=$(openssl rand -base64 32)

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
echo "Monitor ProxYSQL : // "
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

echo "#########################################"
echo "Install MariaDB Server"
echo "#########################################"


./install-mariadb-server.sh -m "${MARIADB_SERVERS}" -U "${SSH_USER}" -s '' -u "${DBA_USER}" -p"${DBA_PASSWORD}"

set +x
IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "create user to ${SSH_USER}@${mariadb}"

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT ALL ON *.* to ${PMACONTROL_USER}@'%' IDENTIFIED BY '${PMACONTROL_PASSWORD}' WITH GRANT OPTION;"
    
    # boucle proxy

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT USAGE ON *.* to ${PROXYSQL_USER}@'%' IDENTIFIED BY '${PROXYSQL_PASSWORD}' WITH GRANT OPTION;"

    ip1=$(echo ${mariadb} | cut -f 1 -d ".")
    ip2=$(echo ${mariadb} | cut -f 2 -d ".")
    ip3=$(echo ${mariadb} | cut -f 3 -d ".")

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT REPLICATION CLIENT,REPLICATION SLAVE ON *.* to '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';"
    

    # ssh ${SSH_USER}@${mariadb} "mysql -e " 2>&1 
done

# set up replication 

echo "###################################################################"
echo "SET UP REPLICATION"
echo "###################################################################"
MASTER=$(echo ${MARIADB_SERVERS} | cut -f 1 -d ",")

mysql -h ${MASTER} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "SHOW MASTER STATUS"

mysql_user=${DBA_USER}
mysql_password=${DBA_PASSWORD}



ct_mysql_query "${MASTER}" 'SHOW MASTER STATUS'
ct_mysql_parse

IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do

    if [[ "${mariadb}" != "${MASTER}" ]]; then

        echo "Serveur : ${mariadb}"
        echo "CHANGE MASTER TO MASTER_HOST='${MASTER}', MASTER_PORT=3306,MASTER_USER='${REPLICATION_USER}', MASTER_PASSWORD='${REPLICATION_PASSWORD}', MASTER_LOG_FILE='${MYSQL_FILE_1}', MASTER_LOG_POS=${MYSQL_POSITION_1};"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "CHANGE MASTER TO MASTER_HOST='${MASTER}', MASTER_PORT=3306,MASTER_USER='${REPLICATION_USER}', MASTER_PASSWORD='${REPLICATION_PASSWORD}', MASTER_LOG_FILE='${MYSQL_FILE_1}', MASTER_LOG_POS=${MYSQL_POSITION_1};"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "START SLAVE;"
        sleep 1
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "SHOW SLAVE STATUS\G"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "set global read_only=1;"
    fi
done
echo "###################################################################"
echo "end set up replication"
echo "###################################################################"

./install-proxysql.sh -p "${PROXYSQL_SERVERS}" -m "${MARIADB_SERVERS}" -u ${PROXYSQL_USER} -P "${PROXYSQL_PASSWORD}" -s '' -U "${SSH_USER}" -a "${PROXYSQLADMIN_USER}" -b "${PROXYSQLADMIN_PASSWORD}" -o "${PROXYSQL_USER}" -r "${PROXYSQL_PASSWORD}"


# TODO : take in consideration of all server are not in same /24
#ip1=$(hostname -I | cut -d' ' -f1 | cut -f 1 -d ".")
#ip2=$(hostname -I | cut -d' ' -f1 | cut -f 2 -d ".")
#ip3=$(hostname -I | cut -d' ' -f1 | cut -f 3 -d ".")

#mysql -e "GRANT REPLICATION CLIENT,REPLICATION SLAVE ON *.* to replication@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'10.82.131.5' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"

#CHANGE MASTER TO MASTER_HOST='10.112.5.14', MASTER_USER='replication', MASTER_PASSWORD='d937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI', MASTER_LOG_FILE='mariadb-bin.000001', MASTER_LOG_POS=923;

#mysql -e "GRANT USAGE ON *.* TO proxysql@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'UIlvRolnc1RYzLZweB4kEZGthhSyd9A6oEs1sTKZ39Y';"

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
echo "Install termined successfully !"


rm -rf "${tmp_file}"
rm -rf "${error_mysql}"

echo "INSERT INTO PMACONTROL"
PMACONTROL_WEBSERVICE_USER=$(openssl rand -base64 16)
PMACONTROL_WEBSERVICE_PASSWORD=$(openssl rand -base64 32)

webservice=$(mktemp)
secret=$(mktemp)
server_json=$(mktemp)

cat > ${webservice} << EOF
{
"webservice": [{
    "user": "${PMACONTROL_WEBSERVICE_USER}",
    "host": "%",
    "password": "${PMACONTROL_WEBSERVICE_PASSWORD}",
    "organization": "Dalenys"
  }]
}
EOF

echo "ajout du compte webservice"
cd /srv/www/pmacontrol && ./glial Webservice addAccount ${webservice} --debug


echo "Insertion des serveurs MariaDB :"

IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do

cat > ${server_json} << EOF
{
    "mysql": [{
            "fqdn": "${mariadb}",
            "display_name": "@hostname",
            "port": "3306",
            "login": "${PMACONTROL_USER}",
            "password": "${PMACONTROL_PASSWORD}",
            "tag": ["${TAG}"],
            "organization": "${CLIENT}",
            "environment": "${ENVIRONMENT}",
            "ssh_ip": "${mariadb}",
            "ssh_port": "22"
    }],
}
EOF
    res=$(curl --insecure -v -K ${secret} -F "conf=@${server_json}" "https://127.0.0.1/en/webservice/pushServer")
    echo $res
done

echo "Insertion des serveurs ProxySQL :"

IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
for proxysql in "${PROXYSQL_SERVER[@]}"; do

cat > ${server_json} << EOF
{
    "mysql": [{
            "fqdn": "${proxysql}",
            "display_name": "@hostname",
            "port": "6033",
            "login": "${PMACONTROL_USER}",
            "password": "${PMACONTROL_PASSWORD}",
            "tag": ["${TAG}"],
            "organization": "${CLIENT}",
            "environment": "${ENVIRONMENT}",
            "ssh_ip": "${proxysql}",
            "ssh_port": "22"
    }],
}
EOF
    res=$(curl --insecure -v -K ${secret} -F "conf=@${server_json}" "https://127.0.0.1/en/webservice/pushServer")
    echo $res
done


echo "TODO : effacer le compte web service"
echo ""
echo "############################"
echo "ALL INSTALLATION COMPLETED !"
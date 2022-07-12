#!/bin/bash
set +x
set -euo pipefail

while getopts 'hm:p:u:P:s:U:a:b:' flag; do
  case "${flag}" in
    h)
        echo "auto install mariadb"
        echo "example : ./install-proxysql.sh -s '10.68.68.179' -p '10.68.68.179,10.68.68.180' -o '10.114.5.13'"
        echo " "
        echo "options:"

        echo "-m ip1,ip2,ip3          specify the list of mysql server coma separated"
        echo "-p ip1,ip2              specify the list of proxysql server"
        echo "-u                      specify user for MySQL"
        echo "-P                      specify password for MySQL"
        echo "-U                      specify user for SSH (default ROOT)"
        echo "-a                      specify admin account for proxySQL"
        echo "-b                      specify password account for proxySQL"
        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    p) PROXYSQL_SERVERS="${OPTARG}" ;;
    u) MYSQL_USER="${OPTARG}" ;;
    P) MYSQL_PASSWORD="${OPTARG}" ;;
    U) SSH_USER="${OPTARG}"   ;;
    s) SERVER_TO_INSTALL="${OPTARG}" ;;
    a) PROXYSQLADMIN_USER="${OPTARG}" ;;
    b) PROXYSQLADMIN_PASSWORD="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

#echo "server : ${SERVER_TO_INSTALL}\n"

if [[ ! -z "${SERVER_TO_INSTALL}" ]]
then
    whoami
    who=$(whoami)
    echo "whoami : ${who}"


    echo "SSH_USER=${SSH_USER}"
    echo "MARIADB_SERVERS=${MARIADB_SERVERS}"
    echo "PROXYSQL_SERVERS=${PROXYSQL_SERVERS}"
    echo "MYSQL_USER=${MYSQL_USER}"
    echo "MYSQL_PASSWORD=${MYSQL_PASSWORD}"
    echo "SERVER_TO_INSTALL=${SERVER_TO_INSTALL}"
    echo "PROXYSQLADMIN_USER=${PROXYSQLADMIN_USER}"
    echo "PROXYSQLADMIN_PASSWORD=${PROXYSQLADMIN_PASSWORD}"


    if [[ "root" != "${who}" ]]
    then 
        sudo -s
    fi
    apt install -y curl

    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s

    apt update
    apt upgrade -y

    apt install -y mariadb-client

    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    
    echo "Test mysql account for ProxySQL"
    for i in "${MARIADB_SERVER[@]}"; do
        if ! mysql --connect-timeout=5 -h ${i} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e 'use mysql'; then
            echo "Impossible to MySQL connect to server ${i} from ProxySQL ${SERVER_TO_INSTALL} with ${MYSQL_USER}//${MYSQL_PASSWORD}"
            exit 1;
        fi
    done

    apt -y install wget
    apt -y install gnupg2
    apt -y install lsb-release

    wget -O - 'https://repo.proxysql.com/ProxySQL/repo_pub_key' | apt-key add -

    echo deb https://repo.proxysql.com/ProxySQL/proxysql-2.3.x/$(lsb_release -sc)/ ./ | tee /etc/apt/sources.list.d/proxysql.list

    apt update
    apt-get install proxysql

    echo "Proxysql SQL installed"

    systemctl start proxysql

    echo "Proxysql SQL up & running"

    mysql -u admin -padmin -P 6032 -e "UPDATE global_variables SET variable_value='${PROXYSQLADMIN_USER}:${PROXYSQLADMIN_PASSWORD}' WHERE variable_name='admin-admin_credentials';"
    mysql -u admin -padmin -P 6032 -e "SAVE ADMIN VARIABLES TO DISK;"

    cat > /root/.my.cnf << EOF
[client]
user=${PROXYSQLADMIN_USER}
password=${PROXYSQLADMIN_PASSWORD}
host=127.0.0.1
port=6032
EOF

    cat /root/.my.cnf

    echo "restart proxysql"
    systemctl restart proxysql


    mysql -e "update global_variables set variable_value='${PROXYSQLADMIN_USER}' where variable_name='admin-cluster_username';"
    mysql -e "update global_variables set variable_value='${PROXYSQLADMIN_PASSWORD}' where variable_name='admin-cluster_password';"

    mysql -e "LOAD ADMIN VARIABLES TO RUNTIME;"
    mysql -e "SAVE ADMIN VARIABLES TO DISK;"



    for proxysql in "${PROXYSQL_SERVER[@]}"; do
        mysql -e "INSERT INTO proxysql_servers(hostname, port,weight,comment) VALUES ('${proxysql}', 6032,0,'ProxySQL : ${proxysql}');"
    done

    mysql -e "SAVE PROXYSQL SERVERS TO DISK"
    mysql -e "LOAD PROXYSQL SERVERS TO RUNTIME;"
    
else
    IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
    
    for proxysql in "${PROXYSQL_SERVER[@]}"; do

        echo "######################################################"
        echo "# Connect to ${proxysql}"
        echo "######################################################"
        
        echo "cat $0 | ssh ${SSH_USER}@${proxysql} SSH_USER=${SSH_USER} MARIADB_SERVERS=${MARIADB_SERVERS} PROXYSQL_SERVERS=${PROXYSQL_SERVERS} MYSQL_USER=${MYSQL_USER} MYSQL_PASSWORD=${MYSQL_PASSWORD} SERVER_TO_INSTALL=${proxysql} PROXYSQLADMIN_USER=${PROXYSQLADMIN_USER} PROXYSQLADMIN_PASSWORD=${PROXYSQLADMIN_PASSWORD} '/bin/bash'"
        cat $0 | ssh ${SSH_USER}@${proxysql} SSH_USER=${SSH_USER} MARIADB_SERVERS=${MARIADB_SERVERS} PROXYSQL_SERVERS=${PROXYSQL_SERVERS} MYSQL_USER=${MYSQL_USER} MYSQL_PASSWORD=${MYSQL_PASSWORD} SERVER_TO_INSTALL=${proxysql} PROXYSQLADMIN_USER=${PROXYSQLADMIN_USER} PROXYSQLADMIN_PASSWORD=${PROXYSQLADMIN_PASSWORD} '/bin/bash'
        #ssh root@MachineB 'bash -s' < $0 $@ -s "${proxysql}"

    done
fi
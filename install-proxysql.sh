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
        echo "-p ip1,ip2              specify the list of proxysql server"
        echo "-u                      specify user for MySQL"
        echo "-P                      specify password for MySQL"
        echo "-U                      specify user for SSH (default ROOT)"

        exit 0
    ;;
    m) MARIADB_SERVERS="${OPTARG}" ;;
    p) PROXYSQL_SERVERS="${OPTARG}" ;;
    u) MYSQL_USER="${OPTARG}" ;;
    P) MYSQL_PASSWORD="${OPTARG}" ;;
    U) SSH_USER="${OPTARG}"   ;;
    s) SERVER_TO_INSTALL="${OPTARG}" ;;
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
    systemctl start proxysql

    echo "Proxysql SQL up & running"

    mysql -u admin -padmin -P 6032 -e "UPDATE global_variables SET variable_value='external:DdkC9WxjPG4ts0P4cGU3KfhttsvJ4BTHXj7dEWW3Y' WHERE variable_name='admin-admin_credentials';"
    mysql -u admin -padmin -P 6032 -e "SAVE ADMIN VARIABLES TO DISK;"

    cat > /root/.my.cnf << EOF
[client]
user=external
password=DdkC9WxjPG4ts0P4cGU3KfhttsvJ4BTHXj7dEWW3Y
port=6032
EOF

    echo "restart proxysql"
    systemctl restart proxysql

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
        
        cat $0 | ssh ${SSH_USER}@${proxysql} SSH_USER=${SSH_USER} MARIADB_SERVERS=${MARIADB_SERVERS} PROXYSQL_SERVERS=${PROXYSQL_SERVERS} MYSQL_USER=${MYSQL_USER} MYSQL_PASSWORD=${MYSQL_PASSWORD} SERVER_TO_INSTALL=${proxysql} '/bin/bash'
        #ssh root@MachineB 'bash -s' < $0 $@ -s "${proxysql}"

    done
fi
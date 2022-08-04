#!/bin/bash
set +x
set -euo pipefail

tmp_file=$(mktemp)
error_mysql=$(mktemp)
DEBUG="true"


HTTP_PROXY=''

path=${BASH_SOURCE%/*}
source $path/lib/6t-mysql-client.sh
source $path/lib/6t-debug.sh


while getopts 'hm:p:o:t:a:u:s:c:e:y:' flag; do
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
        echo "-y                      proxy to get internet"

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
    y) HTTP_PROXY="${OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done


PATH_DIRECTORY_PASSWORD='password'
MD5=$(md5sum <<<"$0" | cut -d ' ' -f 1)
echo "MD5 : ${MD5}" 

mkdir -p ${PATH_DIRECTORY_PASSWORD}
password_file="${PATH_DIRECTORY_PASSWORD}/${CLIENT}-${ENVIRONMENT}-${TAG}-${MD5}.secret"

if [ ! -f ${password_file} ]
then
    echo "File does not exist in Bash"
    PMACONTROL_USER="pmacontrol"
    PMACONTROL_PASSWORD=$(openssl rand -base64 32)

    MONITOR_USER="monitor"
    MONITOR_PASSWORD=$(openssl rand -base64 32)

    REPLICATION_USER="replication_slave"
    REPLICATION_PASSWORD=$(openssl rand -base64 32)

    PROXYSQLADMIN_USER="proxysql"
    PROXYSQLADMIN_PASSWORD=$(openssl rand -base64 32)

    DBA_USER="dba"
    DBA_PASSWORD=$(openssl rand -base64 32)


    cat > ${password_file} << EOF
#!/bin/bash
# MYSQL ACCOUNT
PMACONTROL_USER=${PMACONTROL_USER}
PMACONTROL_PASSWORD=${PMACONTROL_PASSWORD}
MONITOR_USER=${MONITOR_USER}
MONITOR_PASSWORD=${MONITOR_PASSWORD}
REPLICATION_USER=${REPLICATION_USER}
REPLICATION_PASSWORD=${REPLICATION_PASSWORD}
DBA_USER=${DBA_USER}
DBA_PASSWORD=${DBA_PASSWORD}
# PROXYSQL ADMIN 
PROXYSQLADMIN_USER=${PROXYSQLADMIN_USER}
PROXYSQLADMIN_PASSWORD=${PROXYSQLADMIN_PASSWORD}
EOF


else
    echo "File found. Do something meaningful here"
    source ${password_file}
fi


echo "#################################################"
echo "# PASSWORD GENERATION "
echo "#################################################"
echo ""
echo "#################################################"
echo "MySQL"
echo "#################################################"
echo "PmaControl         : ${PMACONTROL_USER} // ${PMACONTROL_PASSWORD}"
echo "Monitor (ProxySQL) : ${MONITOR_USER} // ${MONITOR_PASSWORD}"
echo "Replication        : ${REPLICATION_USER} // ${REPLICATION_PASSWORD}"
echo "DBA                : ${DBA_USER} // ${DBA_PASSWORD}"
echo ""
echo "#################################################"
echo "ProxySQL Admin"
echo "#################################################"
echo "ProxySQL ADMIN : ${PROXYSQLADMIN_USER} // ${PROXYSQLADMIN_PASSWORD}"
echo ""

function test_url {
  response=$(curl --write-out %{http_code} --silent --output /dev/null $1)
  filename=$( echo $1 | cut -f1 -d"/" )
  if [ "$QUIET" = false ] ; then echo -n "$p "; fi

  if [ $response -eq 200 ] ; then
    # website working
    if [ "$QUIET" = false ] ; then
      echo -n "$response "; echo -e "\e[32m[ok]\e[0m"
    fi
    # remove .temp file if exist.
    if [ -f cache/$filename ]; then rm -f cache/$filename; fi
  else
    # website down
    if [ "$QUIET" = false ] ; then echo -n "$response "; echo -e "\e[31m[DOWN]\e[0m"; fi
    if [ ! -f cache/$filename ]; then
        while read e; do
            # using mailx command
            echo "$p WEBSITE DOWN" | mailx -s "$1 WEBSITE DOWN" $e
            # using mail command
            #mail -s "$p WEBSITE DOWN" "$EMAIL"
        done < $EMAILLISTFILE
        echo > cache/$filename
    fi
  fi
}

whoami
who=$(whoami)
echo "whoami : ${who}"

sudo=''
if [[ "${who}" != "root" ]]
then
    echo "Passage avec SUDO"
    sudo='sudo'
fi

#test ssh connection all
IFS=',' read -ra SERVERS <<< "${MARIADB_SERVERS},${PROXYSQL_SERVERS}"
for server in "${SERVERS[@]}"; do
    echo "connect to ${SSH_USER}@${server}"
    ssh ${SSH_USER}@${server} "whoami" 2>&1 
done

echo "#########################################"
echo "Install MariaDB Server"
echo "#########################################"


./install-mariadb-server.sh -m "${MARIADB_SERVERS}" -U "${SSH_USER}" -s '' -u "${DBA_USER}" -p"${DBA_PASSWORD}" -y "${HTTP_PROXY}"

set +x
IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do
    echo "create user to ${SSH_USER}@${mariadb}"

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT ALL ON *.* to ${PMACONTROL_USER}@'%' IDENTIFIED BY '${PMACONTROL_PASSWORD}' WITH GRANT OPTION;"
    
    # boucle proxy

    mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "GRANT USAGE ON *.* to ${MONITOR_USER}@'%' IDENTIFIED BY '${MONITOR_PASSWORD}' WITH GRANT OPTION;"


    #TODO add each IP to replication slave
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
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "STOP SLAVE; RESET SLAVE ALL;"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "CHANGE MASTER TO MASTER_HOST='${MASTER}', MASTER_PORT=3306,MASTER_USER='${REPLICATION_USER}', MASTER_PASSWORD='${REPLICATION_PASSWORD}', MASTER_LOG_FILE='${MYSQL_FILE_1}', MASTER_LOG_POS=${MYSQL_POSITION_1};"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "START SLAVE;"
        sleep 1
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "SHOW SLAVE STATUS\G"
        mysql -h ${mariadb} -u "${DBA_USER}" -p"${DBA_PASSWORD}" -e "set global read_only=1;"
    else


        ct_mysql_query "${MASTER}" "SELECT PASSWORD FROM mysql.user WHERE user='${PMACONTROL_USER}'"
        ct_mysql_parse

        HASH_PMACONTROL=${MYSQL_PASSWORD_1}

        ct_mysql_query "${MASTER}" "SELECT SUBSTRING_INDEX(@@version, '-', 1) as VERSION;"
        ct_mysql_parse


        MYSQL_VERSION=${MYSQL_VERSION_1}

    fi
done
echo "###################################################################"
echo "end set up replication"
echo "###################################################################"



echo "###################################################################"
echo "PROXYSQL START !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "###################################################################"

./install-proxysql.sh -p "${PROXYSQL_SERVERS}" -m "${MARIADB_SERVERS}" -u ${MONITOR_USER} -P "${MONITOR_PASSWORD}" -s '' -U "${SSH_USER}" -a "${PROXYSQLADMIN_USER}" -b "${PROXYSQLADMIN_PASSWORD}" -o "${MONITOR_USER}" -r "${MONITOR_PASSWORD}"

echo "###################################################################"
echo "PROXYSQL END !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "###################################################################"

# TODO : take in consideration of all server are not in same /24
#ip1=$(hostname -I | cut -d' ' -f1 | cut -f 1 -d ".")
#ip2=$(hostname -I | cut -d' ' -f1 | cut -f 2 -d ".")
#ip3=$(hostname -I | cut -d' ' -f1 | cut -f 3 -d ".")

#mysql -e "GRANT REPLICATION CLIENT,REPLICATION SLAVE ON *.* to replication@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"
#mysql -e "GRANT ALL ON *.* to pmacontrol@'10.82.131.5' IDENTIFIED BY 'd937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI';"

#CHANGE MASTER TO MASTER_HOST='10.112.5.14', MASTER_USER='replication', MASTER_PASSWORD='d937jkF19KCfc9xfkCiL8Q2D2l1UhOroQpIv6zHLvQI', MASTER_LOG_FILE='mariadb-bin.000001', MASTER_LOG_POS=923;

#mysql -e "GRANT USAGE ON *.* TO proxysql@'${ip1}.${ip2}.${ip3}.%' IDENTIFIED BY 'UIlvRolnc1RYzLZweB4kEZGthhSyd9A6oEs1sTKZ39Y';"


echo "Ajout du Pmacontrol pour proxySQL"
IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
for proxysql in "${PROXYSQL_SERVER[@]}"; do

    echo "ProxySQL server : ${proxysql}"

    echo "mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p${PROXYSQLADMIN_PASSWORD}"

    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "update global_variables set variable_value='${MYSQL_VERSION}' where variable_name='mysql-server_version';"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "update global_variables set variable_value='false' where variable_name='mysql-multiplexing';"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "LOAD MYSQL VARIABLES TO RUNTIME;"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "SAVE MYSQL VARIABLES TO DISK;"

    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "DELETE FROM mysql_users where username='${PMACONTROL_USER}'"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "INSERT INTO mysql_users (username, password, active, default_hostgroup) VALUES ('${PMACONTROL_USER}','${HASH_PMACONTROL}', 1, 10);"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "LOAD MYSQL USERS TO RUNTIME;"
    mysql -P 6032 -h ${proxysql} -u ${PROXYSQLADMIN_USER} -p"${PROXYSQLADMIN_PASSWORD}" -e "SAVE MYSQL USERS TO DISK;"
done

echo ""
echo "###################################################################"
echo "Install termined successfully !"
echo "###################################################################"
echo ""

rm -rf "${tmp_file}"
rm -rf "${error_mysql}"

echo "INSERT INTO PMACONTROL"
PMACONTROL_WEBSERVICE_USER=$(openssl rand -base64 16)
PMACONTROL_WEBSERVICE_PASSWORD=$(openssl rand -base64 32)

webservice=$(mktemp)
secret=$(mktemp)


echo "user=${PMACONTROL_WEBSERVICE_USER}:${PMACONTROL_WEBSERVICE_PASSWORD}" > $secret


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
cd /srv/www/pmacontrol && $sudo ./glial administration all --debug
cd /srv/www/pmacontrol && $sudo ./glial Webservice addAccount ${webservice} --debug


echo "Insertion des serveurs MariaDB :"


    path_import='/srv/www/pmacontrol/configuration/import'
    $sudo mkdir -p $path_import




IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
for mariadb in "${MARIADB_SERVER[@]}"; do

server_json="${path_import}/${ENVIRONMENT}-${TAG}-${mariadb}-mariadb.json"

$sudo bash -c "cat > ${server_json} << EOF
{
    \"mysql\": [{
            \"fqdn\": \"${mariadb}\",
            \"display_name\": \"@hostname\",
            \"port\": \"3306\",
            \"login\": \"${PMACONTROL_USER}\",
            \"password\": \"${PMACONTROL_PASSWORD}\",
            \"tag\": [\"${TAG}\"],
            \"organization\": \"${CLIENT}\",
            \"environment\": \"${ENVIRONMENT}\",
            \"ssh_ip\": \"${mariadb}\",
            \"ssh_port\": \"22\"
    }]
}
EOF"

	res=$($sudo curl -v -K ${secret} -F "conf=@${server_json}" "http://127.0.0.1/pmacontrol/en/webservice/pushServer")
    #res=$($sudo curl --insecure -v -K ${secret} -F "conf=@${server_json}" "https://127.0.0.1/en/webservice/pushServer")
    echo $res
	sleep 1
done

echo "Insertion des serveurs ProxySQL :"

IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
for proxysql in "${PROXYSQL_SERVER[@]}"; do

server_json="${path_import}/${ENVIRONMENT}-${TAG}-${proxysql}-proxy.json"

$sudo bash -c "cat > ${server_json} << EOF
{
    \"mysql\": [{
            \"fqdn\": \"${proxysql}\",
            \"display_name\": \"@hostname\",
            \"port\": \"6033\",
            \"login\": \"${PMACONTROL_USER}\",
            \"password\": \"${PMACONTROL_PASSWORD}\",
            \"tag\": [\"${TAG}\"],
            \"organization\": \"${CLIENT}\",
            \"environment\": \"${ENVIRONMENT}\",
            \"ssh_ip\": \"${proxysql}\",
            \"ssh_port\": \"22\"
    }]
}
EOF"


#    code=$(curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1/pmacontrol/en/webservice/pushServer)
#    code2=$(curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1/pmacontrol/en/webservice/pushServer)
#    code3=$(curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1/en/webservice/pushServer)
#    code4=$(curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1/en/webservice/pushServer)





	

    res=$($sudo curl -v -K ${secret} -F "conf=@${server_json}" "http://127.0.0.1/pmacontrol/en/webservice/pushServer")
    echo $res
	sleep 1
done


echo "TODO : effacer le compte web service"
echo ""
echo "############################"
echo "ALL INSTALLATION COMPLETED !"

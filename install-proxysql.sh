#!/bin/bash
set +x
set -euo pipefail

while getopts 'hm:p:u:P:s:U:a:b:o:r:' flag; do
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
        echo "-o                      specify account for monitor proxySQL"
        echo "-r                      specify account for monitor proxySQL (password)"
        echo "-y                      proxy for connect to internet"
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
    o) MONITOR_USER="${OPTARG}" ;;
    r) MONITOR_PASSWORD="${OPTARG}" ;;


    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done



#echo "server : ${SERVER_TO_INSTALL}\n"

if [[ ! -z "${SERVER_TO_INSTALL}" ]]
then

    HTTP_PROXY=''

    function getProxy()
    {
        cat /etc/apt/apt.conf.d/* | { grep -E 'Acquire::https::proxy' | grep -Eo 'https?://.*([0-9]+|/)' || true;}
    }

    HTTP_PROXY=$(getProxy)

    export http_proxy=${HTTP_PROXY}
    export https_proxy=${HTTP_PROXY}

    who=$(whoami)
 
    sudo=''
    if [[ "${who}" != "root" ]]
    then
        echo "Passage avec SUDO"
        
        sudo="sudo https_proxy=${HTTP_PROXY} http_proxy=${HTTP_PROXY}"
    fi
    
    $sudo apt install -y ntp
    $sudo service ntp stop
    $sudo ntpd -gq
    $sudo service ntp start
    sleep 1

    $sudo apt update
    $sudo apt upgrade -y

    if [ ! -f "/etc/apt/sources.list.d/mariadb.list" ]
    then
        echo "add repo mariadb"
        echo "################"
        $sudo apt install -y curl
        $sudo curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | $sudo bash -s
    else
        echo "repo mariadb there !"
    fi
    
    $sudo apt install -y mariadb-client

    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    
    echo "Test mysql account for ProxySQL"
    for i in "${MARIADB_SERVER[@]}"; do
        if ! mysql --connect-timeout=5 -h ${i} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e 'use mysql'; then
            echo "Impossible to MySQL connect to server ${i} from ProxySQL ${SERVER_TO_INSTALL} with ${MYSQL_USER}//${MYSQL_PASSWORD}"
            exit 1;
        fi
    done

    $sudo apt -y install wget
    $sudo apt -y install gnupg2
    $sudo apt -y install lsb-release
    $sudo apt -y install nmap

    wget -O - 'https://repo.proxysql.com/ProxySQL/repo_pub_key' | $sudo apt-key add -

    $sudo echo deb https://repo.proxysql.com/ProxySQL/proxysql-2.3.x/$(lsb_release -sc)/ ./ | $sudo tee /etc/apt/sources.list.d/proxysql.list


    $sudo apt update
    $sudo apt-get install proxysql

    echo "Proxysql SQL installed"

    $sudo systemctl start proxysql

    echo "Proxysql SQL up & running"
    $sudo sleep 2
    echo "end sleep 2"


    $sudo ip a
    $sudo nmap localhost -p 6032
    $sudo nmap $SERVER_TO_INSTALL -p 6032

    mysql -h 127.0.0.1 -u admin -padmin -P 6032 -e "UPDATE global_variables SET variable_value='${PROXYSQLADMIN_USER}:${PROXYSQLADMIN_PASSWORD}' WHERE variable_name='admin-admin_credentials';"
    mysql -h 127.0.0.1 -u admin -padmin -P 6032 -e "SAVE ADMIN VARIABLES TO DISK;"

    echo "add file /root/.my.cnf"

    $sudo bash -c "cat > /root/.my.cnf << EOF
[client]
user=${PROXYSQLADMIN_USER}
password=${PROXYSQLADMIN_PASSWORD}
host=127.0.0.1
#port=6032
EOF"

    $sudo cat /root/.my.cnf

    echo "restart proxysql"
    $sudo systemctl restart proxysql

    sleep 10

    proxyadmin="mysql -h ${SERVER_TO_INSTALL} -u ${PROXYSQLADMIN_USER} -p${PROXYSQLADMIN_PASSWORD} -P 6032"

    echo "proxyadmin"
	$proxyadmin -e "show processlist;"

   $proxyadmin -e "update global_variables set variable_value='${PROXYSQLADMIN_USER}' where variable_name='admin-cluster_username';"
   $proxyadmin -e "update global_variables set variable_value='${PROXYSQLADMIN_PASSWORD}' where variable_name='admin-cluster_password';"
   $proxyadmin -e "LOAD ADMIN VARIABLES TO RUNTIME;"
   $proxyadmin -e "SAVE ADMIN VARIABLES TO DISK;"

    $proxyadmin -e "UPDATE global_variables SET variable_value='${MONITOR_USER}' WHERE variable_name='mysql-monitor_username';"
    $proxyadmin -e "UPDATE global_variables SET variable_value='${MONITOR_PASSWORD}' WHERE variable_name='mysql-monitor_password';"
    $proxyadmin -e "LOAD MYSQL VARIABLES TO RUNTIME;"
    $proxyadmin -e "SAVE MYSQL VARIABLES TO DISK;"

    IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
    
    for proxysql in "${PROXYSQL_SERVER[@]}"; do
       $proxyadmin -e "INSERT INTO proxysql_servers(hostname, port,weight,comment) VALUES ('${proxysql}', 6032,0,'ProxySQL : ${proxysql}');"
    done
    
   $proxyadmin -e "SAVE PROXYSQL SERVERS TO DISK;"
   $proxyadmin -e "LOAD PROXYSQL SERVERS TO RUNTIME;"

    IFS=',' read -ra MARIADB_SERVER <<< "$MARIADB_SERVERS"
    
    echo "Test mysql account for ProxySQL"
    for i in "${MARIADB_SERVER[@]}"; do

       $proxyadmin -e "INSERT INTO mysql_servers VALUES(10,'${i}',3306,0,'ONLINE',1,0,1000,10,0,0,'read server and write server');"
       $proxyadmin -e "INSERT INTO mysql_servers VALUES(20,'${i}',3306,0,'ONLINE',1,0,1000,10,0,0,'read server');"
    done

   $proxyadmin -e "INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, comment) VALUES (10, 20, 'Master / Slave');"
   $proxyadmin -e "LOAD MYSQL SERVERS TO RUNTIME;"
   $proxyadmin -e "SAVE MYSQL SERVERS TO DISK;"

    #regles de routage
   $proxyadmin -e "INSERT INTO mysql_query_rules (active, match_digest, destination_hostgroup, apply) VALUES (1, '^SELECT.*',20, 0);"
   $proxyadmin -e "INSERT INTO mysql_query_rules (active, match_digest, destination_hostgroup, apply) VALUES (1, '^SELECT.* FOR UPDATE',10, 1);"

   $proxyadmin -e "LOAD MYSQL QUERY RULES TO RUNTIME;"
   $proxyadmin -e "SAVE MYSQL QUERY RULES TO DISK;"


    #mysql --defaults-file=/etc/mysql/debian.cnf -B -e "select CONCAT('INSERT INTO mysql_users (username, password, active, default_hostgroup) VALUES (\'',User,'\',\'',Password,'\', 1, 10);') from mysql.user where password != '' and host = '%' group by user;"
    # LOAD MYSQL USERS TO RUNTIME;
    # SAVE MYSQL USERS TO DISK;
    
else
    IFS=',' read -ra PROXYSQL_SERVER <<< "$PROXYSQL_SERVERS"
    
    for proxysql in "${PROXYSQL_SERVER[@]}"; do

        echo "######################################################"
        echo "# Connect to ${proxysql} to install proxysql" 
        echo "######################################################"
        
        cat $0 | ssh ${SSH_USER}@${proxysql} SSH_USER=${SSH_USER} MARIADB_SERVERS=${MARIADB_SERVERS} PROXYSQL_SERVERS=${PROXYSQL_SERVERS} MYSQL_USER=${MYSQL_USER} MYSQL_PASSWORD=${MYSQL_PASSWORD} SERVER_TO_INSTALL=${proxysql} PROXYSQLADMIN_USER=${PROXYSQLADMIN_USER} PROXYSQLADMIN_PASSWORD=${PROXYSQLADMIN_PASSWORD} MONITOR_USER=${MONITOR_USER} MONITOR_PASSWORD=${MONITOR_PASSWORD} '/bin/bash'
        #ssh root@MachineB 'bash -s' < $0 $@ -s "${proxysql}"

    done
fi



apt update
apt -y upgrade


cd /srv/code/toolkit

git pull 

./set-hostname.sh -h 68k-orchestrator

./install-mariadb.sh -p dfghSTHSRTHSRTYJUJSDFGDFYJH -v 10.8 -d /srv/mysql

apt -y install jq libjq1 libonig5

password_file="/root/orchestrator.secret"


    ORCHESTRATOR_MONITOR_USER="orchestrator_monitor"
    ORCHESTRATOR_MONITOR_PASSWORD=$(openssl rand -base64 32)

    ORCHESTRATOR_USER="orchestrator"
    ORCHESTRATOR_PASSWORD=$(openssl rand -base64 32)


    cat > "${password_file}" << EOF
#!/bin/bash
# ORCHESTRATOR ACCOUNT
ORCHESTRATOR_MONITOR_USER=${ORCHESTRATOR_MONITOR_USER}
ORCHESTRATOR_MONITOR_PASSWORD=${ORCHESTRATOR_MONITOR_PASSWORD}
ORCHESTRATOR_USER=${ORCHESTRATOR_USER}
ORCHESTRATOR_PASSWORD=${ORCHESTRATOR_PASSWORD}

EOF




wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator_3.2.6_amd64.deb
wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-sysv-3.2.6_amd64.deb
wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-cli_3.2.6_amd64.deb
wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-cli-sysv-3.2.6_amd64.deb


wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-client_3.2.6_amd64.deb
wget https://github.com/openark/orchestrator/releases/download/v3.2.6/orchestrator-client-sysv-3.2.6_amd64.deb


dpkg -i *.deb


reboot

wait .....


service orchestrator start

mysql -e "CREATE DATABASE IF NOT EXISTS orchestrator;"
mysql -e "CREATE USER '${ORCHESTRATOR_USER}'@'127.0.0.1' IDENTIFIED BY '${ORCHESTRATOR_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON \`orchestrator\`.* TO '${ORCHESTRATOR_USER}'@'127.0.0.1';"


cat > "/etc/orchestrator.conf.json" << EOF
{
  "Debug": true,
  "EnableSyslog": false,
  "ListenAddress": ":3000",
  "MySQLTopologyUser": "${ORCHESTRATOR_MONITOR_USER}",
  "MySQLTopologyPassword": "${ORCHESTRATOR_MONITOR_PASSWORD}",
  "MySQLTopologyCredentialsConfigFile": "",
  "MySQLTopologySSLPrivateKeyFile": "",
  "MySQLTopologySSLCertFile": "",
  "MySQLTopologySSLCAFile": "",
  "MySQLTopologySSLSkipVerify": true,
  "MySQLTopologyUseMutualTLS": false,
  "MySQLOrchestratorHost": "127.0.0.1",
  "MySQLOrchestratorPort": 3306,
  "MySQLOrchestratorDatabase": "orchestrator",
  "MySQLOrchestratorUser": "${ORCHESTRATOR_USER}",
  "MySQLOrchestratorPassword": "${ORCHESTRATOR_PASSWORD}",
  "MySQLOrchestratorCredentialsConfigFile": "",
  "MySQLOrchestratorSSLPrivateKeyFile": "",
  "MySQLOrchestratorSSLCertFile": "",
  "MySQLOrchestratorSSLCAFile": "",
  "MySQLOrchestratorSSLSkipVerify": true,
  "MySQLOrchestratorUseMutualTLS": false,
  "MySQLConnectTimeoutSeconds": 1,
  "DefaultInstancePort": 3306,
  "DiscoverByShowSlaveHosts": true,
  "InstancePollSeconds": 5,
  "DiscoveryIgnoreReplicaHostnameFilters": [
    "a_host_i_want_to_ignore[.]example[.]com",
    ".*[.]ignore_all_hosts_from_this_domain[.]example[.]com",
    "a_host_with_extra_port_i_want_to_ignore[.]example[.]com:3307"
  ],
  "UnseenInstanceForgetHours": 240,
  "SnapshotTopologiesIntervalHours": 0,
  "InstanceBulkOperationsWaitTimeoutSeconds": 10,
  "HostnameResolveMethod": "default",
  "MySQLHostnameResolveMethod": "@@hostname",
  "SkipBinlogServerUnresolveCheck": true,
  "ExpiryHostnameResolvesMinutes": 60,
  "RejectHostnameResolvePattern": "",
  "ReasonableReplicationLagSeconds": 10,
  "ProblemIgnoreHostnameFilters": [],
  "VerifyReplicationFilters": false,
  "ReasonableMaintenanceReplicationLagSeconds": 20,
  "CandidateInstanceExpireMinutes": 60,
  "AuditLogFile": "",
  "AuditToSyslog": false,
  "RemoveTextFromHostnameDisplay": ".mydomain.com:3306",
  "ReadOnly": false,
  "AuthenticationMethod": "",
  "HTTPAuthUser": "",
  "HTTPAuthPassword": "",
  "AuthUserHeader": "",
  "PowerAuthUsers": [
    "*"
  ],
  "ClusterNameToAlias": {
    "127.0.0.1": "test suite"
  },
  "ReplicationLagQuery": "",
  "DetectClusterAliasQuery": "SELECT SUBSTRING_INDEX(@@hostname, '.', 1)",
  "DetectClusterDomainQuery": "",
  "DetectInstanceAliasQuery": "",
  "DetectPromotionRuleQuery": "",
  "DataCenterPattern": "[.]([^.]+)[.][^.]+[.]mydomain[.]com",
  "PhysicalEnvironmentPattern": "[.]([^.]+[.][^.]+)[.]mydomain[.]com",
  "PromotionIgnoreHostnameFilters": [],
  "DetectSemiSyncEnforcedQuery": "",
  "ServeAgentsHttp": false,
  "AgentsServerPort": ":3001",
  "AgentsUseSSL": false,
  "AgentsUseMutualTLS": false,
  "AgentSSLSkipVerify": false,
  "AgentSSLPrivateKeyFile": "",
  "AgentSSLCertFile": "",
  "AgentSSLCAFile": "",
  "AgentSSLValidOUs": [],
  "UseSSL": false,
  "UseMutualTLS": false,
  "SSLSkipVerify": false,
  "SSLPrivateKeyFile": "",
  "SSLCertFile": "",
  "SSLCAFile": "",
  "SSLValidOUs": [],
  "URLPrefix": "",
  "StatusEndpoint": "/api/status",
  "StatusSimpleHealth": true,
  "StatusOUVerify": false,
  "AgentPollMinutes": 60,
  "UnseenAgentForgetHours": 6,
  "StaleSeedFailMinutes": 60,
  "SeedAcceptableBytesDiff": 8192,
  "PseudoGTIDPattern": "",
  "PseudoGTIDPatternIsFixedSubstring": false,
  "PseudoGTIDMonotonicHint": "asc:",
  "DetectPseudoGTIDQuery": "",
  "BinlogEventsChunkSize": 10000,
  "SkipBinlogEventsContaining": [],
  "ReduceReplicationAnalysisCount": true,
  "FailureDetectionPeriodBlockMinutes": 60,
  "FailMasterPromotionOnLagMinutes": 0,
  "RecoveryPeriodBlockSeconds": 3600,
  "RecoveryIgnoreHostnameFilters": [],
  "RecoverMasterClusterFilters": [
    "_master_pattern_"
  ],
  "RecoverIntermediateMasterClusterFilters": [
    "_intermediate_master_pattern_"
  ],
  "OnFailureDetectionProcesses": [
    "echo 'Detected {failureType} on {failureCluster}. Affected replicas: {countSlaves}' >> /tmp/recovery.log"
  ],
  "PreGracefulTakeoverProcesses": [
    "echo 'Planned takeover about to take place on {failureCluster}. Master will switch to read_only' >> /tmp/recovery.log"
  ],
  "PreFailoverProcesses": [
    "echo 'Will recover from {failureType} on {failureCluster}' >> /tmp/recovery.log"
  ],
  "PostFailoverProcesses": [
    "echo '(for all types) Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Successor: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostUnsuccessfulFailoverProcesses": [],
  "PostMasterFailoverProcesses": [
    "echo 'Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Promoted: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostIntermediateMasterFailoverProcesses": [
    "echo 'Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Successor: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostGracefulTakeoverProcesses": [
    "echo 'Planned takeover complete' >> /tmp/recovery.log"
  ],
  "CoMasterRecoveryMustPromoteOtherCoMaster": true,
  "DetachLostSlavesAfterMasterFailover": true,
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "PreventCrossDataCenterMasterFailover": false,
  "PreventCrossRegionMasterFailover": false,
  "MasterFailoverDetachReplicaMasterHost": false,
  "MasterFailoverLostInstancesDowntimeMinutes": 0,
  "PostponeReplicaRecoveryOnLagMinutes": 0,
  "OSCIgnoreHostnameFilters": [],
  "GraphiteAddr": "",
  "GraphitePath": "",
  "GraphiteConvertHostnameDotsToUnderscores": true,
  "ConsulAddress": "",
  "ConsulAclToken": "",
  "ConsulKVStoreProvider": "consul"
}


EOF
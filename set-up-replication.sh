
#!/bin/bash

##############################################################################
#                                                                            #
# PmaControl Toolkit                                                         #
#                                                                            #
#                                                                            #
# Module: set-up-replication                                                 #
#                                                                            #
# Author: Aurélien LEQUOY                                                    #
# Email:  aurelien@68koncept.com                                             #
#                                                                            #
#                                                                            #
##############################################################################
# test en PP

#https://devops.stackexchange.com/questions/4503/access-vault-secret-from-bash-script

set +x
set -euo pipefail
IFS=$'\n\t'

mysql_repl_user='replication'
mysql_repl_password=$(date +%s | sha256sum | base64 | head -c 32)

ssh_user='root'
ssh_password=''

mysql_user='root'
mysql_password=''

master=""
slave=""
CONNECTION_NAME=""
DEBUG=false
VERBOSE=false
LIBRARY="ct-library"
SCRIPT_BEFORE=''
SCRIPT_AFTER=''
CT_FORCE=''

while getopts 'hm:s:t:u:p:U:P:o:S:i:w:d:b:a:fv' flag; do
  case "${flag}" in
    h)
        echo "Set up a Mysql replicaton master / slave"
        echo "example : ./install -c config_sample/config.sample.json"
        echo " "
        echo "options:"
		echo "-h   Display this help "
		echo "######################################## Server ########################################"
        echo "-m   [*]          New Master (Connect to the server on the given host.)"
        echo "-s   [*]          New Slave  (Connect to the server on the given host.)"
		echo "######################################## MySQL ########################################"
        echo "-t   [ ]          Connection Name's thread replication M/S - default empty)"
		echo "                  |-> Only compatible with MariaDB"
        echo "-u   [ ]          MySQL's user     (with GRANT SUPER),     - default: root"
        echo "-p   [*]          MySQL's password (with GRANT SUPER),     - default: (none)"
		echo "-U   [ ]          MySQL's user (used for replication)      - default: replication"
		echo "-P   [ ]          MySQL's password (used for replication)  - default: generated"
		echo "-o   [ ]          MySQL's Options comma separated (only on slave)"
	    echo "-B   [ ]          MySQL's database for replication coma separated"
		echo "                                                           - default: --all-databases"
	    echo "######################################### SSH #########################################"
		echo "-S   [ ]          Ssh's user"
		echo "-i   [-]          Ssh's key Selects a file from which the identity "
		echo "                  |-> (private key) for public key authentication is read."
		echo "-w   [-]          Ssh's password"
		echo "-d   [ ]          Directory where is stored temporary backup on slave"
		echo "-i or -w of this option is mandatory"
		echo "-b   [ ]          Script will be executed before set up the replication (M&S)"
		echo "-a   [ ]          Script will be executed after set up the replication (M&S)"
		#echo "######################################## Other ########################################"
		echo "-c   [ ]          Set up a config file with all paramters"+
		echo "-f   [ ]          [WARNING] Force if error or warning"
		echo "######################################## Debug ########################################"
		echo "-v   [ ]          Verbose mode"
		echo "-r   [ ]          Dry run (Only show all commands without execute)"	
		echo ""
		echo "[*] mendatory parameter"
        exit 0
    ;;
	m) master="${OPTARG}";;
	s) slave="${OPTARG}";;
	t) CONNECTION_NAME="${OPTARG}";;
	u) mysql_user="${OPTARG}";;
	p) mysql_password="${OPTARG}";;
	U) mysql_repl_user="${OPTARG}";;
	P) mysql_repl_password="${OPTARG}";;
	o) OPTIONS="${OPTARG}";;
	B) DATABASE="${OPTARG}";;
	S) ssh_user="${OPTARG}";;
	i) ssh_private_key="${OPTARG}";;
	w) ssh_password="${OPTARG}";;
	d) TEMP_DIRECTORY="${OPTARG}/tmp_backup";;
	b) SCRIPT_BEFORE="${OPTARG}";;
	a) SCRIPT_AFTER="${OPTARG}";;
    c) CONFIG_FILE="${OPTARG}";;
	f) CT_FORCE=true ;;
	v) DEBUG=true ;;
    *) echo "Unexpected option ${flag}" 
	   echo "help : bash $0 -h"
        exit 1
    ;;
  esac
done

#read configuration

#test de variable en entré
if [[ -z ${master} ]]; then
	echo "[ERROR] : master host required '$0 -m 127.0.0.1'"
	exit 1
fi

#test de variable en entré
if [[ -z ${slave} ]]; then
	echo "[ERROR] : slave host required '$0 -s 127.0.0.1'"
	exit 1
fi

servers=(
	$master
	$slave
)

CRLIB=$(command -v ct-library)

if [[ -f $CRLIB ]]; then 
	source ${LIBRARY}
else
	echo "[ERROR] : Impossible to find ${LIBRARY} !"
fi

debug "debug mode activated"

# try all connection before start script
function test_all()
{
	if [[ DEBUG == true ]]; then
		debug 'echo "Test all connections :"'
		debug 'echo ""'
	fi

	#test mysql's connection for all servers
	for server in ${servers[@]}; do
		ct_mysql_query $server 'SELECT 1 as "result";'
		ct_mysql_parse ${tmp_file}

		cat ${tmp_file}

		if [[ "1" != "1" ]];
		then
			echo "[mysql][ERROR] Cannot connect in ${mysql_user} to ${server}"
			exit 14
		fi
	done

	#test ssh's connection for all servers
	for server in ${servers[@]}; do
		ct_ssh $server 'whoami'
		
		res="${res//$'\r'}"
		#echo "good : ${res//$'\r'}"

		if [[ "${res}" != "root" ]];
		then
			debug "echo \"'root' | tr -dc '[:print:]' | od -c\""
			debug "echo ${res} | cat -v"
			debug "echo \"res : Z${res}Z\""

			echo "[ssh][ERROR] Cannot connect in root (user: ${res}) to ${server}"
			exit 14
		fi
	done
}

test_all

if [[ ${SCRIPT_BEFORE} != "" ]]; then
	ct_ssh "${master}" "${SCRIPT_BEFORE}"
	ct_ssh "${slave}" "${SCRIPT_BEFORE}"
fi

echo ""
echo "Start script :"

ct_mysql_query $master 'SHOW MASTER STATUS'
ct_mysql_parse


master_log_file=$MYSQL_FILE_1
master_log_pos=$MYSQL_POSITION_1


if [ -z ${master_log_file} ]
then
	echo "[mysql][ERROR] You are not using binary logging"
	exit 3
fi

echo "MASTER_LOG_FILE=${master_log_file}"
echo "MASTER_LOG_POS=${master_log_pos}"

ct_mysql_query $master "SELECT host from mysql.user where user='${mysql_repl_user}';"


grant="GRANT REPLICATION SLAVE ON *.* TO ${mysql_repl_user}@'%' IDENTIFIED BY '${mysql_repl_password}';"

if [ -z "${res}" ]
then
	ct_mysql_query $master "${grant}"
else

	if [[ ${CT_FORCE} == true ]]; then

		ct_mysql_query $master "DROP USER ${mysql_repl_user}@'%';"
		ct_mysql_query $master "${grant}"
	else
		echo "[WARNING] User : ${mysql_repl_user} already exist !!"
		exit 1
	fi
	
	#need check grant
fi


mydumper="mydumper -h ${master} -u ${mysql_user} -p ${mysql_password} -P 3306 -G -E -R -o ${TEMP_DIRECTORY} 2>&1"

ct_ssh $slave "${mydumper}"


myloader="myloader -h ${slave} -u ${mysql_user} -p ${mysql_password} -P 3306 -d ${TEMP_DIRECTORY} 2>&1"

ct_ssh $slave "${myloader}"


########## make backup (connect to slave in ssh and make backup from the master)
########## loading backup

ct_mysql_query $slave "SHOW SLAVE STATUS"
ct_mysql_parse

#if [[ $MYSQL_SLAVE_SQL_RUNNING_1 == "Yes" || $MYSQL_SLAVE_SQL_RUNNING_1 == "Yes" ]]

change_master="CHANGE MASTER TO MASTER_HOST='${master}', MASTER_PORT=3306, MASTER_USER='${mysql_repl_user}', MASTER_PASSWORD='${mysql_repl_password}', MASTER_LOG_FILE='${master_log_file}', MASTER_LOG_POS=${master_log_pos}"
debug "${change_master}"


ct_mysql_query $slave "STOP SLAVE;"
ct_mysql_query $slave "${change_master}"
ct_mysql_query $slave "START SLAVE;"


ct_mysql_query $slave "SHOW SLAVE STATUS"
ct_mysql_parse


if [[ "${SCRIPT_AFTER}" != "" ]]; then
	ct_ssh "${master}" "${SCRIPT_AFTER}"
	ct_ssh "${slave}" "${SCRIPT_AFTER}"
fi

finish

#!/bin/bash 

path=${BASH_SOURCE%/*}


tmp_file=$(mktemp)
error_mysql=$(mktemp)


source $path/lib/6t-mysql-client.sh
source $path/lib/6t-debug.sh

mysql_user=root
mysql_password=NGIyMGEwZThiM2QxZDYxMWRkZDNlZTEy


ct_mysql_query 'localhost' 'SHOW MASTER STATUS'
ct_mysql_parse


master_log_file=$MYSQL_FILE_1
master_log_pos=$MYSQL_POSITION_1


echo "master_log_file = $master_log_file"
echo "master_log_pos = $master_log_pos"



rm -rf "${tmp_file}"
rm -rf "${error_mysql}"
#!/bin/bash 
# 
# Author: Christophe Casalegno / Brain 0verride
# Contact: brain@christophe-casalegno.com
# Version 1.1
#
# Author: Aurélien LEQUOY / TIman
# Contact: aurelienlequoy@gmail.com
# Version 1.2
#
# Copyright (c) 2021-2023
#
# This program is free software: you can redistribute it and/or modify
#
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>
#
# The license is available on this server here:
# https://www.christophe-casalegno.com/licences/gpl-3.0.txt
#
# backup.cfg format
# ROOT_SCRIPT:/srv/code/toolkit/ # Where is your script
# MYSQL_BACKUP_USER:backup # Your MySQL / MariaDB backup user 
# MYSQL_USER_PASS:mypassword # Your MySQL / MariaDB backup user password
# MYSQL_LOCAL_ROOT:/srv/mysql/backup # Where you want to do local MySQL / MariaDB backups
# MYSQL_LOCAL_RETENTION:4 # Local MySQL / MariaDB backup retention
# MYSQL_DB_LIST:databases.txt # The name of the file that contain MySQL / MariaDB databases list (no need to change)

ROOT_SCRIPT="/srv/code/toolkit/"
CONF_FILE="${ROOT_SCRIPT}backup-mysqldump.cfg"
MY_DATE=$(date +"%Y-%m-%d_%H-%M-%S")

function read_config()
{
        CONF_FILE="$1"

        if [[ ! -f "$CONF_FILE" ]]
        then
                MYSQL_BACKUP_USER='root'
                MYSQL_USER_PASS='my_secret_password'

                conf_file=$(ls -tr /etc/mysql/param-* | tail -n 1)

                if [[ -f "$conf_file" ]]; then

                        MYSQL_BACKUP_USER=$(grep "^BCKUSER=" $conf_file | cut -d'"' -f2)
                        MYSQL_USER_PASS=$(grep "BCKPASS=" $conf_file | cut -d'"' -f2)
                fi

                cat > "$CONF_FILE" << EOF
ROOT_SCRIPT:/srv/code/toolkit
MYSQL_BACKUP_USER:'$MYSQL_BACKUP_USER'
MYSQL_USER_PASS:'$MYSQL_USER_PASS'
MYSQL_LOCAL_ROOT:/srv/mysql/backup
MYSQL_LOCAL_RETENTION:4
MYSQL_DB_LIST:databases.txt
EOF
        fi

        VAR_CONF=$(cat "$CONF_FILE")

        for LINE in $VAR_CONF
        do
                VARNAME1=${LINE%%:*}
                VARNAME2=${VARNAME1^^}
                VAR=${LINE#*:}
                eval "${VARNAME2}"="$VAR"
        done
}

read_config "$CONF_FILE"

# Bases de données (MySQL / MariaDB) 

function formatandlog()
{
	INTROFORMAT="$1"
	TARGETFORMAT="$2"
	CHAIN2FORMAT="$3"
	GREEN="\e[32m"
	YELLOW="\e[33m"
	RED="\e[31m"
	ENDCOLOR="\e[0m"

	if [[ "${TARGETFORMAT}" = 'N' ]]
	then
		echo "${INTROFORMAT} ${CHAIN2FORMAT}"
	elif [[ "${TARGETFORMAT}" = 'O' ]]
	then
		echo -e "${INTROFORMAT} ${GREEN}${CHAIN2FORMAT}${ENDCOLOR}"
	elif [[ "${TARGETFORMAT}" = 'W' ]]
	then
		echo -e "${INTROFORMAT} ${YELLOW}${CHAIN2FORMAT}${ENDCOLOR}"
	elif [[ "${TARGETFORMAT}" = 'E' ]]
	then
		echo -e "${INTROFORMAT} ${RED}${CHAIN2FORMAT}${ENDCOLOR}"
	else
		echo 'format not specified'
	fi
}

function checktest()
{
	if [ "$2" -eq 0 ]
	then
		formatandlog "$1" O "OK"
    else
    	formatandlog "$1" E "ERROR"
fi
}

# Fonction pour vérifier si une commande est disponible
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function check_command(){
	cmd=(
		mysql
		mysqldump
		pigz
		gzip
		mysqlshow
		date
		mkdir
	)

	for command in "${cmd[@]}"; do
		if ! command_exists "$command"; then
			checktest "$command is not installed" 99
    		else
			checktest "$command is installed" 0
		fi
	done
}

function mysql_local_backupdir() 
{
	MYSQL_LOCAL_ROOT="$1"
	
	if [[ ! -e "$MYSQL_LOCAL_ROOT" ]]
	then
		echo "$MYSQL_LOCAL_ROOT doesn't exist"
		mkdir "$MYSQL_LOCAL_ROOT"
	else
		if [[ ! -d "$MYSQL_LOCAL_ROOT" ]]
		then
			echo "$MYSQL_LOCAL_ROOT is a file"
			exit 1
		else
			echo "$MYSQL_LOCAL_ROOT is a directory"
		fi
	fi
	
	mkdir "$MYSQL_LOCAL_ROOT"/"$MY_DATE"
	mkdir "$MYSQL_LOCAL_ROOT"/"$MY_DATE"/logs
}

function mysql_backup_list() 
{
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	MYSQL_BACKUP_USER="$3"
	MYSQL_USER_PASS="$4"

	sql="select SCHEMA_NAME from information_schema.SCHEMATA where SCHEMA_NAME NOT IN ('sys', 'information_schema', 'performance_schema');"

	mysql -u "$MYSQL_BACKUP_USER" -p"$MYSQL_USER_PASS" -NB -e "$sql" > "/$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST"
	checktest "mysqlshow" "$?"
} 

function mysql_backup() 
{
	COMPRESSOR="pigz"
	MYSQL_LOCAL_ROOT="$1"
	MYSQL_DB_LIST="$2"
	i=1
	while read -r DB_NAME
	do
		echo "Dumping $DB_NAME..."
		mysqldump -u"$MYSQL_BACKUP_USER" -p"$MYSQL_USER_PASS" "$DB_NAME" \
		--dump-date --master-data=2 --add-locks --no-autocommit --set-gtid-purged=OFF --single-transaction --hex-blob --triggers -R -E \
			| "$COMPRESSOR" > "$MYSQL_LOCAL_ROOT/$MY_DATE/$i-$DB_NAME.sql.gz" \
			2>>"$MYSQL_LOCAL_ROOT/$MY_DATE/logs/$DB_NAME-error.log"
		checktest "mysqldump_$DB_NAME" "$?"
		i=$((i+1))
	done < /"$MYSQL_LOCAL_ROOT"/"$MYSQL_DB_LIST"
} 

function mysql_purge_old_backup() {

	MYSQL_LOCAL_ROOT="$1"
	MYSQL_LOCAL_RETENTION="$2"

	if [ ! -d "$MYSQL_LOCAL_ROOT" ]
	then
		exit 0
	else
		find "$MYSQL_LOCAL_ROOT" -mtime +"$MYSQL_LOCAL_RETENTION" -exec rm -rf {} \;
		checktest "mysqlpurge" "$?"
	fi
}

function do_mysql_backup()
{
	MYSQL_LOCAL_ROOT=$1
	MYSQL_DB_LIST=$2
	MYSQL_LOCAL_RETENTION=$3
	
	check_command
	mysql_local_backupdir "$MYSQL_LOCAL_ROOT"
	mysql_backup_list "$MYSQL_LOCAL_ROOT" "$MYSQL_DB_LIST" "$MYSQL_BACKUP_USER" "$MYSQL_USER_PASS"
	mysql_backup "$MYSQL_LOCAL_ROOT" "$MYSQL_DB_LIST" 
	mysql_purge_old_backup "$MYSQL_LOCAL_ROOT" "$MYSQL_LOCAL_RETENTION"
} 

do_mysql_backup "$MYSQL_LOCAL_ROOT" "$MYSQL_DB_LIST" "$MYSQL_LOCAL_RETENTION"

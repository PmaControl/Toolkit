#!/bin/bash

set -euo pipefail

#name_file=$(echo $0 | cut -d '.' -f2)
#CONF_FILE="$namefile.cfg"

source ./backup-mysqldump.cfg

function mysql_purge_old_backup()
{
        MYSQL_LOCAL_ROOT="$1"
        MYSQL_LOCAL_RETENTION="$2"

        if [ ! -d "$MYSQL_LOCAL_ROOT" ]
        then
                exit 0;
        else
                find "$MYSQL_LOCAL_ROOT" -mtime +"$MYSQL_LOCAL_RETENTION" -exec rm -rf {} \;
        fi
}

function do_mysql_backup()
{

        MYSQL_LOCAL_ROOT="$1"
        MYSQL_DB_LIST="$2"
        MYSQL_LOCAL_RENTENTION="$3"

        mysql_local_backupdir $MYSQL_LOCAL_ROOT
        mysql_backup_list  $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST
        mysql_purge_old_backup $MYSQL_LOCAL_ROOT $MYSQL_LOCAL_RETENTION
}

function mysql_backup_list()
{
        MYSQL_LOCAL_ROOT="$1"
        MYSQL_DB_LIST="$2"
    MYSQL_BACKUP_USER="$3"
    MYSQL_BACKUP_PASS="$4"

        mysql -u "$MYSQL_BACKUP_USER" -p"$MYSQL_BACKUP_PASS" -ND -e "SHOW DATABASES" > "/$MYSQL_LOCAL_ROOT/$MYSQL_DB_LIST"
}

function mysql_local_backupdir()
{
        MYSQL_LOCAL_ROOT="$1"
        MY_DATE=$(date +"%Y-%m-%d-%H-%i-%s")

        if [ ! -d "MYSQL_LOCAL_ROOT" ]
        then
                mkdir -p "$MYSQL_LOCAL_ROOT"
        fi

        #mkdir -p "$MYSQL_LOCAL_ROOT"/"$MY_DATE"
        mkdir -p "$MYSQL_LOCAL_ROOT"/"$MY_DATE"/logs
}

function mysql_backup()
{
        COMPRESSOR="pigz"
        MY_DATE=$(date +"%y-%m-%d-%H")
        MYSQL_LOCAL_ROOT="$1"
        MYSQL_DB_LIST="$2"
        MYSQLDUMP_OPTIONS="--dump-date --no-autocommit --signe-transation --hex-blob --trigger -ER --master-data=2"

        while read DB_NAME
        do
                echo "Dumping $DB_NAME..."
                mysqldump -u"$MYSQL_BACKUP_USER" -p"$MYSQL_BACKUP_PASS" "$DB_NAME" ${MYSQLDUMP_OPTIONS} \
                        | "$COMPRESSOR" > "$MYSQL_LOCAL_ROOT/$MY_DATE/$DB_NAME-$MY_DATE.sql.gz" \
                        2>> "$MYSQL_LOCAL_ROOT/$MYDATE/logs/$DB_NAME-$MYDATE-error.log"
        done < /"$MYSQL_LOCAL_ROOT"/"$MYSQL_DB_LIST"
}

function dir_backup_list()
{
        ROOT_SCRIPT="$1"
        BACKUP_DIR_LIST="$2"
        ls -d -- /*/ | grep -v -w "media\-" | cut -d "/" -f2 >/"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"
}

function dir_remote_backup()
{
    BACKUP_SERVER_DST="$1"
    BACKUP_SERVER_NAME="$2"
    BACKUP_SERVER_ROOT="$3"
    BACKUP_DIR_LIST="$4"
    BACKUP_COMMAND="$5"

    while read dir2backup
    do
        echo "Backuping $dir2backup..."
        $BACKUP_COMMAND /"$dir2backup" "$BACKUP_SERVER_DST"@"$BACKUP_SERVER_NAME"::"$BACKUP_SERVER_ROOT/$BACKUP_SERVER_DST"/"$dir2backup"
    done < /"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"
}

function dir_remote_purge()
{
    BACKUP_SERVER_DST="$1"
    BACKUP_SERVER_NAME="$2"
    BACKUP_SERVER_ROOT="$3"
    BACKUP_DIR_LIST="$4"
    DIR_REMOTE_RETENTION="$5"
    BACKUP_COMMAND="$6"

    while read dir2backup
    do
        echo "Cleaning $dir2backup..."
        $BACKUP_COMMAND $DIR_REMOTE_RETENTION "$BACKUP_SERVER_DST"@"$BACKUP_SERVER_NAME"::/"$BACKUP_SERVER_ROOT/$BACKUP_SERVER_DST"/"$dir2backup"
    done < /"$ROOTSCRIPT"/"$BACKUP_DIR_LIST"

}

#dir_backup_list "$ROOTSCRIPT" "$BACKUP_DIR_LIST"
#dir_remote_backup "$BACKUP_SERVER_DST" "$BACKUP_SERVER_NAME" "$BACKUP_SERVER_ROOT" "$BACKUP_DB_LSIT" "$BACKUP_COMMAND"
#dir_remote_purge "$BACKUP_SERVER_DST" "$BACKUP_SERVER_NAME" "$BACKUP_SERVER_ROOT" "$BACKUP_DB_LSIT" "$DIR_REMOTE_RETENTION" "$BACKUP_COMMAND"

do_mysql_backup $MYSQL_LOCAL_ROOT $MYSQL_DB_LIST $MYSQL_LOCAL_RETENTION

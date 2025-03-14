#!/bin/bash

# source lib/crc32-string.sh

set -euo pipefail
IFS=$'\n\t'

VERSION='10.7'
CLUSTER_NAME='68Koncept'
CLUSTER_MEMBER=''
PASSWORD=''
SSD='false'
SPIDER='false'
CLUSTER='OFF'
PURGE='false'
DATADIR='/var/lib/mysql'
REPO_LOCAL='false'
BOOTSTRAP='false'
DEBIAN_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)

IP_PMACONTROL='localhost'
ADD_TO_PMACONTROL='false'

while getopts 'hp:n:m:xv:cud:rbx:y:a:' flag; do
  case "${flag}" in
    h) 
        echo "auto install mariadb"
        echo "example : ./mariadb.sh -p 'my_password' -c 'Esysteme' -m '127.0.0.1,127.0.0.2,127.0.0.3'"
        echo " "
        echo "options:"
        echo "-p PASSWORD             specify root password for mariadb"
        echo "-n name                 specify the name of galera cluster"
        echo "-m ip1,ip2,ip3          specify the list of member of cluster"
        echo "-v 10.7                 specify the version of MariaDB"
        echo "-g                      specify to activate and make good set up for Spider"
        echo "-c                      set galera cluster ON"
        echo "-u                      [WARNING] purge previous version of MySQL / MariaDB"
        echo "-d		      set datadir of MariaDB (replace of /var/lib/mysql)"
        echo "-r		      if present use current the reposiry, else we install the one from MariaDB"
        echo "-b		      boostrap a new cluster"
        echo "-d                      specify directory where MariaDB will be installed"
        echo "-x		      specify the password for debian-sys-maint (for cluster)"
        echo "-y		      proxy"
        echo "-a		      add server automatically to pmacontrol server,login,password"
        exit 0
    ;;
    p) PASSWORD="${OPTARG}" ;;
    n) CLUSTER_NAME="${OPTARG}" ;;
    m) CLUSTER_MEMBER="${OPTARG}" ;;
    v) VERSION="${OPTARG}" ;;
    c) CLUSTER='ON';;
    u) PURGE='true';;
    d) DATADIR="${OPTARG}";;
    r) REPO_LOCAL='true';;
    b) BOOTSTRAP='true';;
    x) DEBIAN_PASSWORD="${OPTARG}" ;;
    a) ADD_TO_PMACONTROL='true'
       PMA_PARAM="{OPTARG}" ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done


echo "g"

function getProxy()
{
  cat /etc/apt/apt.conf.d/* | { grep -E 'Acquire::https::proxy' | grep -Eo 'https?://.*([0-9]+|/)' || true;}
}


PROXY=$(getProxy)

export http_proxy="${PROXY}"
export https_proxy="${PROXY}"


function purge {
 export DEBIAN_FRONTEND=noninteractive
 rm -rf /etc/mysql/*
 apt-get -qq -y purge "$(dpkg -l | grep mariadb | cut -d ' ' -f 3)"
 apt-get -qq -y purge "$(dpkg -l | grep mysql | cut -d ' ' -f 3)"
 apt-get -qq -y purge "$(dpkg -l | grep percona | cut -d ' ' -f 3)"
 apt-get -qq -y autoremove
 apt-get -qq clean
}

if [ "$PURGE" = "true" ]
then
  purge
fi

function mytest {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $*" >&2

	rm /etc/apt/sources.list.d/mariadb.list
        exit 1;
    fi
    return $status
}

if [[ -z ${VERSION} ]]; 
then 
  VERSION='10.6'
fi

if [[ -z ${PASSWORD} ]]; 
then 
  echo "option -p required (password)"
  echo "for help -h"
  exit 0;
fi

echo "PASSWORD = $PASSWORD"
echo "CLUSTER_NAME = $CLUSTER_NAME"
echo "CLUSTER_MEMBER = $CLUSTER_MEMBER"
echo "VERSION = $VERSION"
echo "DATADIR = $DATADIR"



apt -y install lsb-release

OS=$(lsb_release -cs)

DISTRIB=$(lsb_release -si)
DISTRIB=$(echo "$DISTRIB" | tr '[:upper:]' '[:lower:]')

case "$OS" in
    "jessie")      ;;
    "stretch")     ;;
    "xenial")      ;;
    "zesty")       ;;
    "bionic")      ;;
    "buster")      ;;
    "focal")       ;;
    "bullseye")    ;;
    "jammy")       ;;
    "bookworm")    ;;
    *)
        echo "This version is not supported : '$OS'"
        exit 1;
     ;; 
esac


case "$DISTRIB" in
    "debian")
        ;;
        
    "ubuntu")
        ;;

    *)
        echo "This distribution GNU/Linux is not supported : '$DISTRIB'"
        exit 1;
        ;; 
esac


echo "DISTRIB = $DISTRIB"
echo "OS = $OS"

#import mariadb key


apt -y install lsb-release
apt -y install wget
apt -y install gnupg2
apt -y install bc
apt -y install curl
apt -y install apt-transport-https
apt -y install ca-certificates
apt -y install bsdmainutils
apt -y install openssl

PMACONTROL_PASSWORD=$(openssl rand -base64 40)

if [[ $ADD_TO_PMACONTROL = "true" ]]
then
	PMACONTROL_IP="$(echo $PMA_PARAM | cut -d',' -f1)"	
	PMACONTROL_USER="$(echo $PMA_PARAM | cut -d',' -f2)"
	PMACONTROL_PASSWORD="$(echo $PMA_PARAM | cut -d',' -f3)"

	tmpfile='/tmp/pmcontrol.json'
	cp -a config/pmacontrol.json "${tmpfile}"

	sed "s/{%IP%}/${PMACONTROL_IP}/g" -i "${tmpfile}"
	sed "s/{%PASSWORD%}/${PMACONTROL_PASSWORD}/g" -i "${tmpfile}"
	sed "s/{%IP%}/${PMACONTROL_IP}/g" -i "${tmpfile}"


fi



if [ $REPO_LOCAL = "false" ]
	then

		MARIADB=/etc/apt/sources.list.d/mariadb.list

		if [[ -f "$MARIADB" ]]
		then
			echo "Deleteing existing repositoriy : ${MARIADB}"
			rm "$MARIADB"
		fi


curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-${VERSION}"

#cat > /etc/apt/sources.list.d/mariadb.list << EOF
# MariaDB $VERSION repository list - created 2017-08-10 22:02 UTC
# http://downloads.mariadb.org/mariadb/repositories/
#deb [arch=i386,amd64] http://ftp.igh.cnrs.fr/pub/mariadb/repo/${VERSION}/${DISTRIB} ${OS} main
#deb-src http://ftp.igh.cnrs.fr/pub/mariadb/repo/${VERSION}/${DISTRIB} ${OS} main
#EOF

fi

set +e
mytest apt-get -m -qq -y update
set -e


mytest apt-get -qq -y install software-properties-common


export DEBIAN_FRONTEND=noninteractive



if [ $VERSION = "galera57" ]; then
	debconf-set-selections <<< "mysql-wsrep-server-5.7 mysql-server/root_password password $PASSWORD"
	debconf-set-selections <<< "mysql-wsrep-server-5.7 mysql-server/root_password_again password $PASSWORD"
	 
	mytest apt-get -qq -y install mysql-wsrep-server-5.7 galera-3 > /dev/null
else
	debconf-set-selections <<< "mariadb-server-${VERSION} mysql-server/root_password password $PASSWORD"
	debconf-set-selections <<< "mariadb-server-$VERSION mysql-server/root_password_again password $PASSWORD"
	
	mytest apt-get -qq -y install mariadb-server
fi

IFS=',' read -r -a array <<< "$CLUSTER_MEMBER"

for server in "${array[@]}"
do
    mytest mysql -u root -p"${PASSWORD}" -e "GRANT ALL ON *.* TO sst@'$server' IDENTIFIED BY 'QSEDWGRg133' WITH GRANT OPTION;" 
done

#mytest mysql -u root -p"${PASSWORD}" -e "GRANT ALL ON *.* TO dba@'%' IDENTIFIED BY '$PASSWORD' WITH GRANT OPTION; "

mytest mysql -u root -p"${PASSWORD}" -e "GRANT ALL ON *.* TO root@'localhost' IDENTIFIED BY '${PASSWORD}' WITH GRANT OPTION;"
mytest mysql -u root -p"${PASSWORD}" -e "GRANT ALL ON *.* TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '${DEBIAN_PASSWORD}' WITH GRANT OPTION;"

if [[ "${IP_PMACONTROL}" != 'localhost' ]]
then
	mytest mysql -u root -p"${PASSWORD}" -e "GRANT ALL ON *.* TO 'pmacontrol'@'${IP_PMACONTROL}' IDENTIFIED BY '${PMACONTROL_PASSWORD}' WITH GRANT OPTION;"
fi



echo -e "[client]
user=root
password='$PASSWORD'" > /root/.my.cnf

#version=$(mysql -u root -p$PASSWORD -se "SELECT VERSION()" | sed -n 1p | grep -Po '10\.([0-9]{1,2})')




#ip=`ifconfig | grep -Eo 'inet (a[d]{1,2}r:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1`

ip=$(hostname -I)

echo "IP : ${ip}"

#crc32=`mysql -u root -p$PASSWORD -e "SELECT CRC32('$ip')"`

crc32=$(echo -n "${ip}" | gzip -c | tail -c8 | hexdump -n4 -e '"%u"')

echo "crc32 : $crc32"

id_server=$(echo -n "${crc32}" | cut -d ' ' -f 2 | tr -d '\n')

echo "ID Server : ${id_server}"

hostname=$(hostname)

innodb_buffer_pool_size='512M'
memtotal=$(grep MemTotal /proc/meminfo | awk '{print $2}' | xargs -I {} echo "scale=4; {}/1024^2" | bc)

new_buffer=$(echo "${memtotal} * 0.75" | bc -l)

innodb_buffer_pool_size=$(echo "${new_buffer}" | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')

mytest service mysql stop > /dev/null
#mytest /etc/init.d/mysql stop > /dev/null

mkdir -p "${DATADIR}/log"
mkdir -p "${DATADIR}/backup"
mkdir -p "${DATADIR}/data"
mkdir -p "${DATADIR}/binlog"
mkdir -p "${DATADIR}/relaylog"
mkdir -p "${DATADIR}/tmp"

cp -pr /var/lib/mysql/* "${DATADIR}/data"

chown mysql:mysql -R "${DATADIR}"

# install xtrabackup

#if [ $REPO_LOCAL = "false" ]
#then
#	wget https://repo.percona.com/apt/percona-release_0.1-5.${OS}_all.deb
#	dpkg -i percona-release_0.1-5.${OS}_all.deb

#	rm percona-release_0.1-5.${OS}_all.deb
#fi

#iptables -A INPUT -p tcp --dport 4444 -j ACCEPT
#iptables -A INPUT -p tcp --dport 4567 -j ACCEPT

cat > /etc/mysql/my.cnf << EOF

# MariaDB database server configuration file.
#
# You can copy this file to one of:
# - "/etc/mysql/my.cnf" to set global options,
# - "~/.my.cnf" to set user-specific options.
# 
# One can use all long options that the program supports.
# Run program with --help to get a list of available options and with
# --print-defaults to see which it would actually understand and use.
#
# For explanations see
# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

# This will be passed to all mysql clients
# It has been reported that passwords should be enclosed with ticks/quotes
# escpecially if they contain "#" chars...
# Remember to edit /etc/mysql/debian.cnf when changing the socket location.
[client]
port            = 3306
socket          = /var/run/mysqld/mysqld.sock

# Here is entries for some specific programs
# The following values assume you have at least 32M ram

# This was formally known as [safe_mysqld]. Both versions are currently parsed.
[mysqld_safe]
socket          = /var/run/mysqld/mysqld.sock
nice            = 0

[mysqld]
#
# * Basic Settings
#

innodb_autoextend_increment = 1000
innodb_strict_mode=0
sql_mode=NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
performance_schema=ON
connect_timeout=10
innodb_rollback_on_timeout=1
wait_timeout=18000

plugin-load=server_audit=server_audit.so

server_audit_logging=1

# do not allow users to uninstall plugin
server_audit=FORCE_PLUS_PERMANENT

# only audit connections and DDL queries
server_audit_events=CONNECT,QUERY_DDL

# flat file
server_audit_output_type=FILE
server_audit_file_path=${DATADIR}/log/audit.log
server_audit_file_rotate_size=1000000
server_audit_file_rotations=9

character-set-server  = utf8mb4 
collation-server      = utf8mb4_general_ci 
character_set_server   = utf8mb4
collation-server = utf8mb4_general_ci
#innodb_force_recovery = 1

user            = mysql
pid-file        = /var/run/mysqld/mysqld.pid
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
basedir         = /usr
datadir         = ${DATADIR}/data
tmpdir          = ${DATADIR}/tmp
lc_messages_dir = /usr/share/mysql
lc_messages     = en_US

plugin_dir = /usr/lib/mysql/plugin/

skip-name-resolve

#logs
log_error=${DATADIR}/log/error.log


#
# Instead of skip-networking the default is now to listen only on
# localhost which is more compatible and is not less secure.
# bind-address           = 127.0.0.1
#
# * Fine Tuning
#
max_connections         = 1000
connect_timeout         = 10
wait_timeout            = 600
max_allowed_packet      = 256M
thread_cache_size       = 128
sort_buffer_size        = 4M
bulk_insert_buffer_size = 16M
tmp_table_size          = 256M
max_heap_table_size     = 256M
#
# * MyISAM
#
# This replaces the startup script and checks MyISAM tables if needed
# the first time they are touched. On error, make copy and try a repair.
myisam_recover_options = BACKUP
key_buffer_size         = 128M
open-files-limit       = 2000
table_open_cache        = 400
myisam_sort_buffer_size = 512M
concurrent_insert       = 2
read_buffer_size        = 2M
read_rnd_buffer_size    = 1M
key_cache_segments      = 64

#mroonga.replicate_rewrite_db="repl->repl2"
#mroonga.replicate_do_table="repl2.article2"

#
# * Query Cache Configuration
#
# Cache only tiny result sets, so we can fit more in the query cache.
query_cache_limit               = 128K
query_cache_size                = 0
# for more write intensive setups, set to DEMAND or OFF
query_cache_type                = OFF
#
# * Logging and Replication
#
# Both location gets rotated by the cronjob.
# Be aware that this log type is a performance killer.
# As of 5.1 you can enable the log at runtime!
general_log_file        = $DATADIR/log/general.log
#general_log             = 1
#
# Error logging goes to syslog due to /etc/mysql/conf.d/mysqld_safe_syslog.cnf.
#
# we do want to know about network errors and such
log_warnings            = 2
#
# Enable the slow query log to see queries with especially long duration
slow_query_log=1
slow_query_log_file     = $DATADIR/log/mariadb-slow.log
long_query_time=1
#log_slow_rate_limit    = 1000
log_slow_verbosity      = query_plan
log_slave_updates       = 1
#log-queries-not-using-indexes
#log_slow_admin_statements
#
# The following can be used as easy to replay backup logs or for replication.
# note: if you are setting up a replication slave, see README.Debian about
#       other settings you may need to change.
server-id               = $id_server

report_host            = $hostname

#auto_increment_increment = 2
#auto_increment_offset  = 1
log_bin                        = $DATADIR/binlog/mariadb-bin
log_bin_index          = $DATADIR/binlog/mariadb-bin.index
# not fab for performance, but safer
#sync_binlog            = 1
expire_logs_days        = 10

#to be more easy for SHOW BINLOG EVENTS (1G => 100M)
max_binlog_size         = 100M

# slaves
relay_log              = ${DATADIR}/relaylog/relay-bin
relay_log_index        = ${DATADIR}/relaylog/relay-bin.index
relay_log_info_file   = ${DATADIR}/relaylog/relay-bin.info

log_slave_updates

#read_only

#
# If applications support it, this stricter sql_mode prevents some
# mistakes like inserting invalid dates etc.
# sql_mode               = NO_ENGINE_SUBSTITUTION,TRADITIONAL
#
# * InnoDB
#
# InnoDB is enabled by default with a 10MB datafile in /var/lib/mysql/.
# Read the manual for more InnoDB related options. There are many!
default_storage_engine  = InnoDB
# you can't just change log file size, requires special procedure
innodb_log_file_size    = 2G
innodb_buffer_pool_size = ${innodb_buffer_pool_size}G
#innodb_buffer_pool_instances=8 ## removed for 10.7
innodb_log_buffer_size  = 8M
innodb_file_per_table   = 1
innodb_open_files       = 400
innodb_io_capacity      = 2000
innodb_flush_method     = O_DIRECT
#
# * Security Features

#
# Read the manual, too, if you want chroot!
# chroot = /var/lib/mysql/
#
# For generating SSL certificates I recommend the OpenSSL GUI "tinyca".
#
# ssl-ca=/etc/mysql/cacert.pem
# ssl-cert=/etc/mysql/server-cert.pem
# ssl-key=/etc/mysql/server-key.pem



#
# * Galera-related settings
event-scheduler = ON
#


[galera]
# Mandatory settings
wsrep_on=$CLUSTER
wsrep_cluster_name='$CLUSTER_NAME'
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_address=gcomm://$CLUSTER_MEMBER
wsrep_node_address=$ip
wsrep_node_name=$hostname
wsrep_gtid_mode=ON

wsrep_sst_method = xtrabackup-v2
wsrep_sst_auth = 'sst:QSEDWGRg133'

wsrep_provider_options="gcache.size = 20G"
wsrep_max_ws_rows = 500000


binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2

#
# Allow server to accept connections on all interfaces.
#
bind-address=0.0.0.0
#
# Optional setting
wsrep_slave_threads=4
innodb_flush_log_at_trx_commit=2

# DBUG options for wsrep provider
#wsrep_dbug_option

# Generate fake primary keys for non-PK tables (required for multi-master
# and parallel applying operation)
wsrep_certify_nonPK=1

# Location of the directory with data files. Needed for non-mysqldump
# state snapshot transfers. Defaults to mysql_real_data_home.
#wsrep_data_home_dir=

# Maximum number of rows in write set
wsrep_max_ws_rows=131072

# Maximum size of write set
wsrep_max_ws_size=1073741824

# to enable debug level logging, set this to 1
wsrep_debug=0

# convert locking sessions into transactions
wsrep_convert_LOCK_to_trx=0

# how many times to retry deadlocked autocommits
wsrep_retry_autocommit=1

# change auto_increment_increment and auto_increment_offset automatically
wsrep_auto_increment_control=1

# replicate myisam
## wsrep_replicate_myisam=1 #removed in 10.7



# retry autoinc insert, which failed for duplicate key error
wsrep_drupal_282555_workaround=0

# enable "strictly synchronous" semantics for read operations
wsrep_causal_reads=0

# Protocol version to use
# wsrep_protocol_version=

# log conflicts
wsrep_log_conflicts=1



[xtrabackup]
user=sst
password=QSEDWGRg133
databases-exclude=lost+found

[mysqldump]
quick
quote-names
max_allowed_packet      = 256M

[mysql]
#no-auto-rehash # faster start of mysql but no tab completion

[isamchk]
key_buffer              = 16M

!includedir /etc/mysql/conf.d/

EOF


if [[ -n $DEBIAN_PASSWORD ]]
then

cat > /etc/mysql/debian.cnf << EOF
# Automatically generated for Debian scripts. DO NOT TOUCH!
# Pmacontrol/Toolkit
[client]
host     = localhost
user     = debian-sys-maint
password = $DEBIAN_PASSWORD
socket   = /var/run/mysqld/mysqld.sock
[mysql_upgrade]
host     = localhost
user     = debian-sys-maint
password = $DEBIAN_PASSWORD
socket   = /var/run/mysqld/mysqld.sock
basedir  = /usr

EOF

fi


set +e
mytest apt-get -qq update > /dev/null
set -e
#mytest apt-get -qq install -y percona-toolkit > /dev/null
mytest apt-get -qq install -y tar socat lsof > /dev/null



if [ $BOOTSTRAP = 'true' ]
then 
	{ mytest galera_new_cluster > /dev/null; } 2>&1
else
	{ mytest service mysql start > /dev/null; } 2>&1
	#mytest /etc/init.d/mysql start 2>&1 > /dev/null
fi



#backup
mytest apt-get -qq -y install mydumper > /dev/null


#vim 

mytest apt-get -qq -y install vim > /dev/null
echo -e "syntax on" > /root/.vimrc
echo -e "set mouse=r" >> /root/.vimrc


#others
apt-get -qq install -y tree locate screen iftop htop curl git unzip atop nmap > /dev/null


mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root -p"$PASSWORD" mysql

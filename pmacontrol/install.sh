#!/bin/bash
set +x
#set -euo pipefail


PASSWORD=$(openssl rand -base64 32 | head -c 32)
HOST='localhost'
LOCAL_HOST=$(hostname)
DEBUG=false
SSH_VAR=''


ERROR_LOG="/tmp/error.log"
GENERAL_LOG="/tmp/install.log"

if [[ -f "$ERROR_LOG" ]]
then
  rm "$ERROR_LOG"
fi

if [[ -f "$GENERAL_LOG" ]]
then
  rm "$GENERAL_LOG"
fi

PATH_PMA=${BASH_SOURCE%/*}

while getopts 'hu:s:p:d' flag; do
  case "${flag}" in
    h) 
        echo "auto install mariadb"
        echo "example : ./install -s 10.68.68.196"
        echo " "
        echo "options:"
        echo "-u USER                    user who will be used for install Pmacontrol"
        echo "-s SERVER                  server where will be installed PmaControl"
        echo "-p PASSWORD                specify root password for PmaControl"
        echo "-d DEBUG                   display all logs"
        echo ""
        exit 0
    ;;
    p) PASSWORD="${OPTARG}" ;;
    u) SSH_USER="${OPTARG}" ;;
    s) SSH_HOST="${OPTARG}" ;;
    d) DEBUG=true ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

PACKAGE_LIST="/tmp/$SSH_HOST.list"

if [[ -f $PACKAGE_LIST ]]
then 
    rm "$PACKAGE_LIST"
fi

function display() {
  #echo "Parameter #1 is $1"
  msg=$1
  date=$(date '+%Y-%M-%d %H:%M:%S')
  #echo -e "\e[1;35m[${date}]\e[0m \e[37m${HOST}:\e[0m ${msg}"
  echo -e "\033[1;35m[${date}]\033[0m \033[37m${HOST}:\033[0m ${msg}"
}


trim(){
    if [ $# -ne 1 ]
    then
        echo "USAGE: trim [STRING]"
        return 1
    fi
    s="${1}"
    size_before=${#s}
    size_after=0
    while [ "$size_before" -ne "$size_after" ]
    do
        size_before=${#s}
        s="${s#[[:space:]]}"
        s="${s%[[:space:]]}"
        size_after=${#s}
    done
    echo "${s}"
    return 0
}


execute()
{
    #if [[ $# -gt 1 ]]
    #then
    #    echo "USAGE $#: execute [STRING] [STRIN2] [...]"
    #    return 1
    #fi
    HOST=$SSH_HOST
    SSH_COMMAND="ssh $SSH_USER@$SSH_HOST "

    #set +e
    if [[ -f $1 ]]; then
      # echo "cat $1 | $SSH_COMMAND '/bin/bash'"
      RESULT=$(cat "$1" | $SSH_COMMAND "$SSH_VAR" '/bin/bash' 2> $ERROR_LOG)
      test_error "$1"
    else
      RESULT=$($SSH_COMMAND "$SSH_VAR" "$@" > $GENERAL_LOG 2> $ERROR_LOG)
      test_error "$@"
      
    fi
    #set -e
    RESULT=$(echo $RESULT | sed '/^$/d')
    RESULT=$(trim "$RESULT")
    echo "$RESULT"
    
}


test_log()
{

  local tmp
  if [ $DEBUG = true ]
  then

   if [[ -f "$GENERAL_LOG" ]];
    then 
      size=$(($(wc -c < "$GENERAL_LOG") +0))

      if [[ $size -gt 0 ]]
      then
        sed -i '' '/^$/d' "$GENERAL_LOG"

        tmp=$(cat "$GENERAL_LOG")
        display "[LOG][$GENERAL_LOG] $tmp"
        
      fi
    fi
  fi
}


test_error()
{

  local tmp
   if [[ -f "$ERROR_LOG" ]];
    then 
      # remove warning with apt for debian like
      sed -i '' 's/WARNING: apt does not have a stable CLI interface. Use with caution in scripts.//g' "$ERROR_LOG"
      sed -i '' '/^$/d' "$ERROR_LOG"

      size=$(($(wc -c < "$ERROR_LOG") +0))

      if [[ $size -gt 0 ]]
      then
        tmp=$(cat "$ERROR_LOG" | grep -v "WARNING: apt does not have a stable CLI interface. Use with caution in scripts.")

        display "[COMMAND] $1"
        display "[ERROR][$ERROR_LOG] $tmp"
        exit 2
      fi
    fi
}



HOST=$LOCAL_HOST

LIST_COMMAND=(
  ssh
  nmap
  openssl
  cat
  grep
  sed
)

for COMMAND in "${LIST_COMMAND[@]}"
do
  # command -v will return >0 when the $i is not found
  COLORED_COMMAND="\033[1;95m$COMMAND\033[0m"
	command -v $COMMAND >/dev/null && display "$COLORED_COMMAND command found" && continue || { display "$COLORED_COMMAND command not found."; exit 1; }
done


source "$PATH_PMA/compat.sh"

open_ports=$(nmap "$SSH_HOST" -p 22 | grep open)
open_ports=${open_ports//[^0-9]/ } # remove text
open_ports=$(trim "$open_ports")

if [[ $open_ports -eq 22 ]]
then
  display "$HOST => $SSH_HOST:$open_ports open"
else
  display "[ERROR] $SSH_HOST:$open_ports open"
  exit 1;
fi

HOST=$SSH_HOST
OPERATING_SYSTEM=$(execute "$PATH_PMA/version.sh")
test_log

compat

#PKG_UPDATE
#display "Update repositories"
#display "Upgrade repositories"
#PKG_UPGRADE

for PKG in "${PKG_LIST[@]}"; do
  PKG_INSTALL "$PKG"
done


# install mariadb


for PKG in "${PKG_LIST_2[@]}"; do
  PKG_INSTALL "$PKG"
done



echo "FIN"

exit 1;


cd /tmp
display "cloning repsository Pmacontrol/Toolkit"
git clone https://github.com/PmaControl/Toolkit.git

cd Toolkit
chmod +x install-mariadb.sh


display "Installing MariaDB"
./install-mariadb.sh -v 10.7 -p $password -d /srv/mysql



PKG_LIST=(
php7.3
apache2
graphviz
php7.3-mysql
php7.3-ldap
php7.3-json
php7.3-curl
php7.3-cli
php7.3-mbstring
php7.3-intl
php7.3-fpm
libapache2-mod-php7.3
php7.3-gd
php7.3-xml
mariadb-plugin-rocksdb 
)

for PKG in "${PKG_LIST[@]}"; do
        bash "${path}/apt.sh" -s localhost -m install -p "${PKG}"
done

display "restart MariaDB"
service mysql restart

sleep 1

display "Install RocksDB for MariaDB"
mysql -e  "INSTALL SONAME 'ha_rocksdb'"


a2enmod proxy_fcgi setenvif
a2enconf php7.3-fpm
a2enmod rewrite


sed -i 's/\/var\/www/\/srv\/www/g' /etc/apache2/apache2.conf

sed -i 's/\/var\/www\/html/\/srv\/www/g' /etc/apache2/sites-enabled/000-default.conf

awk '/AllowOverride/ && ++i==3 {sub(/None/,"All")}1' /etc/apache2/apache2.conf > /tmp/xfgh && mv /tmp/xfgh /etc/apache2/apache2.conf

mkdir -p /srv/www/
cd /srv/www/

curl -sS https://getcomposer.org/installer | php --
mv composer.phar /usr/local/bin/composer



cd /srv/www/





ssh -T git@github.com
ret=$(echo $?)

if [[ $ret -eq 1 ]]; then
  git clone git@github.com:PmaControl/PmaControl.git pmacontrol
else
  git clone https://github.com/PmaControl/PmaControl.git pmacontrol
fi

cd pmacontrol

git pull origin develop
git config core.fileMode false

composer install -n

service apache2 restart


pwd_pmacontrol=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
sleep 1
pwd_admin=$(date +%s | sha256sum | base64 | base64 | head -c 32 ; echo)


mysql -e "GRANT ALL ON *.* TO pmacontrol@'127.0.0.1' IDENTIFIED BY '${pwd_pmacontrol}' WITH GRANT OPTION;"


cat > /tmp/config.json << EOF
{
  "mysql": {
    "ip": "127.0.0.1",
    "port": 3306,
    "user": "pmacontrol",
    "password": "${pwd_pmacontrol}",
    "database": "pmacontrol"
  },
  "organization": [
    "68Koncept"
  ],
  "webroot": "/pmacontrol/",
  "ldap": {
    "enabled": false,
    "url": "pmacontrol.68koncept.com",
    "port": 389,
    "bind dn": "CN=pmacontrol-auth,OU=Utilisateurs,OU=No_delegation,DC=intra,DC=pmacontrol",
    "bind passwd": "secret_password",
    "user base": "OU=pmacontrol.com,DC=intra,DC=pmacontrol",
    "group base": "OU=pmacontrol.com,DC=intra,DC=pmacontrol",
    "mapping group": {
      "Member": "CN=",
      "Administrator": "CN=",
      "SuperAdministrator": "CN="
    }
  },
  "user": {
    "Member": null,
    "Administrator": null,
    "Super administrator": [
      {
        "email": "nicolas.dupont@france.com",
        "firstname": "Nicolas",
        "lastname": "DUPONT",
        "country": "France",
        "city": "Paris",
        "login": "admin", 
        "password": "${pwd_admin}"
      }
    ]
  },
  "webservice": [{
    "user": "webservice",
    "host": "%",
    "password": "QDRWSHGqdrtwhqetrHthTH",
    "organization": "68Koncept"
  }]
,
  "ssh": [{
    "user": "pmacontrol",
    "private key": "-----BEGIN RSA PRIVATE KEY-----\nMIIJKQIBAAKCAgEAsLxsW/pqk8VkCh/eUuhXusDLyG72sWz7uJk6Y1V/3lQRXbCX\n8orlGSlpcBwtMnVOAMUdul4/NQ9swDJqfSYMx5+s4hgswiDwqliwNmu8KGP7gseq\ntpB1apOsIGKby8KVkqwpmxyFs4W+dKwcxmPlw+1b5w5aro6keIbcomKAFNqq1nzR\nARBfL+AUEEZKjkK1o3vfzEhYL8nO+zpMzv2TMcbTumw+jjHC+DzKtUILBo/LjjkC\nwyWKva6QArS125itvIMT5pUW6X72RgWByKIUzCJrR+HzWO9zl8FQQeRlZjtCp+9C\n7HwMPiKH4upN2FfwWXSEa+NyYFUuNyjOCdbrRpgX0FfChE4XFklSNhMXdKMu\n-----END RSA PRIVATE KEY-----\n",
    "public key": "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCwvGxb+mqTxWQKH95S6Fe6wMvIbvaxbPu4mTpjVX/eVBFdsJfyiuUZKWlwHC0ydU4AxR26Xj81D2zAMmp9JgzHn6ziGCzCIPCqWLA2a7woY/uCx6q2kHVqk6wgYpvLwpWSrCmbHIWzhb50rBzGY+XD7VvnDlqujqR4htyiYoAU2qrWfNEs5NseGEcQaiRMHe57lw2UTXGbj3Ked+h+n/XngRLV4D01DzaQZ8k45dREe32rUmJZJ3hvE3FI57ICEnVtnrQ8+lQrAoYP0jnYT7eXcIvjHDgyMXKc7fEAyp3b2QG+4J/HxL6K+elFJErLQ2yQlDR9afadnTsBJxFBA2/6yx42Lrp0pMprxKOvhSiMKNiDrP73Jt7d8Z5Z89YN+414Vo2M9713O54IB5H2r88qtdY4fuLzK4d4V39vz6ii5H2aEXIJVsbafLCn/qzbjp7IpoqvuB/3Smp2XW2RnWcZB1NY6diTQkS3MKpblDJILv5UtKN9RCyhRmRHFIM5RyTN21Euuei5bX6WhvEsL7jGo6JDmnXi3tzdAeTUbhPgOd2lX4LECBg9wbhzsezN47S6IGf+72sD/6BCJewKCZ8iheM34pEewDJdUSrg06LDLOr1TrRfaoV1qSsWNDtJVrfae/NTo4oKggxNkkDFkfeHm1pBej37dbMqzDVsKcNoCw=="
  }]
}
EOF



./install -c /tmp/config.json

echo "Login : admin"
echo "Password : ${pwd_pmacontrol}"



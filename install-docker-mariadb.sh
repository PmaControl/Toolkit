#!/bin/bash

#check command if available
# docker openssl mysql pmacontrol 
set -euo pipefail

#cmd=(
#docker
#mysql
#openssl
#curl
#)

#used for port need 5 digit
PREFIX=60000

PMACONTROL_SERVER="127.0.0.1"
PMACONTROL_USER="webservice"
PMACONTROL_PASSWORD="my_secret_password"

MYSQL_PMACONTROL_USER="pmacontrol"
MYSQL_PMACONTROL_PASSWORD=$(openssl rand -hex 16 | base64 | head -c 32)

TMP_USER_PASSWORD=$(mktemp)
TMP_CREDENTIALS=$(mktemp)

touch "$TMP_USER_PASSWORD"

while getopts 'h:u:p:' flag; do
    case "${flag}" in
        
    h) PMACONTROL_SERVER="${OPTARG}" ;;
    u) PMACONTROL_USER="${OPTARG}" ;;
    p) PMACONTROL_PASSWORD="${OPTARG}" ;;
    *) 
        echo "auto install mariadb all version of Docker MariaDB 10.0 to 11.1"
        echo "example : ./$0 -h 127.0.0.1 -u pmacontrol -p password"
        echo " "
        echo "options:"
        echo "-h 127.0.0.1            specify the server of PmaControl"
        echo "-u                      specify user for PmaControl"
        echo "-p                      specify password for MySQL"
        exit 0
  
    exit 0
    ;;
  esac
done

echo "user=$PMACONTROL_USER:$PMACONTROL_PASSWORD" > "$TMP_CREDENTIALS"

# list all version of MariaDB, that we want to install
version=(
10.2
10.3
10.4
10.5
10.6
10.7
10.8
10.9
10.10
10.11
11.0
11.1
)

function get_port()
{

    if [[ $# -ne 1 ]]; then
        echo "Put the number of version in arg"
        exit
    fi   
  
    # else we got 10,1 instead of 10.1 in ubuntu
    # ver=$(echo "$1" | sed 's/,/./g')
    ver="${1//,/.}"

    # shellcheck disable=SC2206
    major_minor=(${ver//./ })  # Sépare la partie entière de la partie décimale
    major=${major_minor[0]}
    minor=${major_minor[1]}

    if [ "$minor" -lt 10 ]; then
        minor="0$minor"
    fi

    if [ "$major" -lt 10 ]; then
        major="0$major"
    fi

    i="${major}${minor}"

    # Calculate the port number for the current version
    port=$((PREFIX+i))

    echo "$port"
}

function drop_mariadb_ct()
{
    #remove all existing docker, update with all mariadb only
    if docker ps -q 2>/dev/null | grep -q .; then
        # shellcheck disable=SC2046
        docker stop $(docker ps -q)
        echo "Tous les conteneurs Docker ont été arrêtés avec succès."
    else
        echo "Aucun conteneur Docker en cours d'exécution."
    fi

    # Supprimer tous les conteneurs Docker
    if docker ps -aq 2>/dev/null | grep -q .; then
        # shellcheck disable=SC2046
        docker rm $(docker ps -aq)
        echo "Tous les conteneurs Docker ont été supprimés avec succès."
    else
        echo "Aucun conteneur Docker à supprimer."
    fi
    
    # Vérifie s'il y a des volumes inutilisés
    if [ -n "$(docker volume ls -qf 'dangling=true')" ]; then
        # Supprime les volumes inutilisés
        # shellcheck disable=SC2046
        docker volume rm $(docker volume ls -qf 'dangling=true')
        echo "Volumes inutilisés supprimés."
    else
        echo "Aucun volume inutilisé trouvé."
    fi
}

function get_ip()
{
    #get IPv4 from host to send it to PmaControl later
    ip=$(hostname -I | tr ' ' '\n' | grep -v '^$' | grep -v ^172 | grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
    echo $ip
}

echo "Following port will be used :"
for ver in "${version[@]}"; do
    port=$(get_port "$ver")
    echo -e "$port"
done

drop_mariadb_ct

# Loop through the MariaDB versions
for ver in "${version[@]}"; do
 
    container_name="MDB$ver"
    if docker ps -a --format "{{.Names}}" | grep -q "$container_name"; then
        echo "Container $container_name already exists. Skipping..."
    else
        echo "Starting container $container_name..."

        # Generate a random password using openssl
        password=$(openssl rand -hex 16 | base64 | head -c 32)

        port=$(get_port "$ver")

        echo "################### $container_name => $port"
        # Run the MariaDB docker container with the calculated port and a random password
        
        hostname=$(echo "mariadb-$ver" | sed 's/\./-/g')

    	docker run --detach -h "$hostname" --name "$container_name" -p "$port:3306" \
            --env MARIADB_ROOT_PASSWORD="$password" \
            --env MARIADB_PASSWORD="$password" mariadb:"$ver" \
            --log-bin \
            --server-id="$port" \
            --performance-schema=on \
            --gtid-domain-id="$port"


        ip_docker=$(get_ip)

        echo "mysql -h $ip_docker -u root -p$password -P $port" >> "$TMP_USER_PASSWORD"
    fi
done

docker ps


echo "Sleeping 10 sec the time mysql will be up ...."
sleep 25

while IFS= read -r line; do
    # Extraction des informations depuis chaque ligne
    echo "$line"
    user=$(echo "$line" | awk '{print $5}')
    ip=$(echo "$line" | awk '{print $3}')
    port=$(echo "$line" | awk '{print $8}')
    password_brut=$(echo "$line" | awk '{print $6}')

    password=${password_brut:2}

    user='root'
    echo "ip:port  : $ip:$port"
    echo "user     : $user"
    echo "password : $password"
    echo "####################"
    # Create a user and grant privileges to the user for the new database

    mysql -h "$ip" -P "$port" -u "$user" -p"$password" -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_PMACONTROL_USER}'@'%' IDENTIFIED BY '${MYSQL_PMACONTROL_PASSWORD}' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    code_error=$?
    
    if [[ $code_error -eq 0 ]]; then
        mysql_version=$(mysql -h "$ip" -P "$port" -u "$MYSQL_PMACONTROL_USER" -p"$MYSQL_PMACONTROL_PASSWORD" -NB -e "SELECT VERSION()")
        TMP_JSON=$(mktemp)
        
        echo "MySQL version : $mysql_version"

        if [[ "127.0.0.1" != "$PMACONTROL_SERVER" ]] ; then
            # the goal is to remove IP from docker but it can made some trouble is main IP start by 172
            ip=$(get_ip)
        fi


        cat <<EOF > "$TMP_JSON"
{
    "mysql": [
        {
            "fqdn": "$ip",
            "display_name": "@hostname",
            "port": "$port",
            "login": "$MYSQL_PMACONTROL_USER",
            "password": "$MYSQL_PMACONTROL_PASSWORD",
            "tag": ["mariadb", "docker"],
            "organization": "Docker",
            "environment": "test",
            "ssh_ip": "$ip",
            "ssh_port": "22"
        }
    ]
}
EOF

        if [[ "127.0.0.1" == "$PMACONTROL_SERVER" ]] 
        then
            # Exécution de la commande pmacontrol (add --debug if needed)
            pmacontrol webservice importFile "${TMP_JSON}"
        else
            echo "Using curl"
            curl -X POST -K "$TMP_CREDENTIALS" -H "Content-Type: application/json" -d "@$TMP_JSON" "http://$PMACONTROL_SERVER/pmacontrol/en/webservice/pushServer/"
            # TODO : Test if pmacontrol directory or not
        fi
    else
        echo "[ERROR] Impossible to set user $MYSQL_PMACONTROL_USER on $ip:$port"
    
    fi
done < "$TMP_USER_PASSWORD"

rm "$TMP_CREDENTIALS"
rm "$TMP_USER_PASSWORD"
rm "$TMP_JSON"

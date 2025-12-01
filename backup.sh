#!/bin/bash
set -euo pipefail
shopt -s nullglob


# Variables
DATE=$(date +"%Y%m%d_%H%M%S")

BACKUP_DIR_DIR="/srv/mysql/backup"
BACKUP_DIR="$BACKUP_DIR_DIR/CURRENT"
PHYSICAL_BACKUP="$BACKUP_DIR/physical_$DATE"
LOGICAL_BACKUP="$BACKUP_DIR/mydumper_$DATE"
LOGICAL_SAVE="$BACKUP_DIR_DIR/mydumper_$DATE"

NAME="backup_$DATE.tar.gz"
ARCHIVE="$BACKUP_DIR/$NAME"
STORE_ARCHIVE="$BACKUP_DIR_DIR/$NAME"

TMP_SOCKET="/tmp/mysqld_temp_3308.sock"
TMP_PORT=3308

MYSQL_USER="root"
MYSQL_PASSWORD=""

MYSQL="mysql -N -B -e"

# Couleur purple
PURPLE="\033[0;35m"
RESET="\033[0m"
COLOR_EXECUTION="\033[0;34m"


# Variable globale pour stocker le temps de début de la dernière fonction
LAST_TIME_G=0

log_msg() {
    local MSG="$1"
    local NOW
    NOW=$(date "+%Y-%m-%d %H:%M:%S")

    # Calcul du temps écoulé si LAST_TIME_G > 0
    local ELAPSED=""
    
    SECS=0

    if [ $LAST_TIME_G -ne 0 ]; then
        SECS=$((SECONDS - LAST_TIME_G))
        local HH=$((SECS/3600))
        local MM=$(( (SECS%3600)/60 ))
        local SS=$((SECS%60))
        ELAPSED=$(printf "%02d:%02d:%02d" "$HH" "$MM" "$SS")
    fi

    # Affichage
    if [ $SECS -ne 0 ]; then
        echo -e "${COLOR_EXECUTION}(Temps d'exécution : ${ELAPSED})${RESET}"
    fi
    echo -e "${PURPLE}[${NOW}]${RESET} [${SECONDS}] ${MSG}"


    # Mise à jour du temps pour la prochaine invocation
    LAST_TIME_G=$SECONDS
}

sleep 1

log_msg "Check dependencies"
for bin in mariadb-backup mydumper mysqld_safe mysqladmin mysql; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "[ERROR] '$bin' is not installed or not in PATH."
        exit 1
    fi
done


sleep 2
log_msg "Chown backup directory"

mkdir -p "$BACKUP_DIR"
chown mysql:mysql "$BACKUP_DIR"
chown mysql:mysql "$BACKUP_DIR_DIR"


sleep 2
log_msg "Drop des anciens backup (On garde les 2 plus recent)"

PWD=$(pwd)

cd "$BACKUP_DIR_DIR"
#ls -1t backup_*.tar.gz 2>/dev/null | tail -n +3 | xargs -r rm -f

files=(backup_*.tar.gz)
rm -f "${files[@]:2}" || true

files=(mydumper_*)
rm -rf "${files[@]:2}" || true

cd "$PWD"

log_msg "rm -rvf $BACKUP_DIR/*"

# j'utilise volontairement pas la variable $BACKUP_DIR au cas celle ci serait laissé vide
rm -rf "$BACKUP_DIR_DIR/CURRENT"/*


log_msg "Is the serveur is started with GALERA  ?"

check_galera() {

    # Vérifie si Galera est activé
    WSREP_ON=$($MYSQL "SHOW GLOBAL VARIABLES LIKE 'wsrep_on';" 2>/dev/null | awk '{print $2}')

    if [ "$WSREP_ON" != "ON" ]; then
        log_msg "❌ Galera n'est PAS activé sur ce serveur."
        return 1
    fi

    # Vérifie le nombre de noeuds dans le cluster
    CLUSTER_SIZE=$($MYSQL "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')

    if [ -z "$CLUSTER_SIZE" ]; then
        log_msg "⚠️  Impossible de déterminer la taille du cluster."
        return 2
    fi

    if [ "$CLUSTER_SIZE" -gt 1 ]; then
        log_msg "Galera est activé et le cluster contient $CLUSTER_SIZE noeuds."
    	return 0
    else
        log_msg "Galera est activé mais le cluster ne contient qu'un seul noeud."
        return 1
    fi
}

stop_mysql_temp() {
    local PORT=$TMP_PORT
    local SOCKET="/tmp/mysqld_temp_$PORT.sock"
    local USER="root"   # adapte si besoin

    # Vérifier si un processus MySQL tourne sur ce port
    if ss -ltnp 2>/dev/null | grep -q ":$PORT "; then
        log_msg "✔ MySQL est actif sur le port $PORT"

        if [ -S "$SOCKET" ]; then
            log_msg "✔ Socket trouvé : $SOCKET"
            mysqladmin --socket="$SOCKET" -u"$USER" shutdown
            if [ $? -eq 0 ]; then
                log_msg "✔ MySQL sur le port $PORT arrêté avec succès."
            else
                log_msg "⚠ Échec lors de la tentative d'arrêt via $SOCKET"
            fi
        else
            log_msg "⚠ Aucun socket trouvé à $SOCKET, arrêt impossible."
        fi
    else
        log_msg "ℹ Aucun MySQL trouvé sur le port $PORT"
    fi
}

if check_galera; then
    log_msg "🎉 Galera is actived and cluster size > 1"

    cmd='SET GLOBAL wsrep_desync=1;'
    log_msg "DESYNC du node : 'mysql> $cmd'"
    DESYNC=$($MYSQL "$cmd")
	
fi

log_msg "Physical backup with mariabackup"
mariadb-backup --backup \
    --target-dir="$PHYSICAL_BACKUP"
    
#    --user=$MYSQL_USER --password=$MYSQL_PASSWORD

log_msg "Prepare backup with mariabackup"
mariabackup --prepare \
    --target-dir="$PHYSICAL_BACKUP"

if check_galera; then
	var=1
	while [ "$var" -gt 0 ]; do
	   # Attendre 1 seconde
	   sleep 1

	   # Vérifier la condition
	   var=$($MYSQL "
	       SELECT 
	           gs.VARIABLE_VALUE >
	           SUBSTRING_INDEX(SUBSTRING_INDEX(gv.VARIABLE_VALUE,'gcs.fc_factor = ',-1), ';', 1) *
	           SUBSTRING_INDEX(SUBSTRING_INDEX(gv.VARIABLE_VALUE,'gcs.fc_limit = ',-1), ';', 1)
	       FROM
	           INFORMATION_SCHEMA.GLOBAL_STATUS gs,
	            INFORMATION_SCHEMA.GLOBAL_VARIABLES gv
        	WHERE gv.VARIABLE_NAME = 'wsrep_provider_options'
	          AND gs.VARIABLE_NAME = 'wsrep_local_recv_queue';
	    ")

    	echo "Boucle: var=$var"
	done

	# Sortir du mode DESYNC
	$MYSQL "SET GLOBAL wsrep_desync=0;"
	log_msg "Resyncro du noeud au sein du cluster"
fi

log_msg "Chown mysql:mysql -R '$PHYSICAL_BACKUP' on the directory"

chown mysql:mysql -R "$PHYSICAL_BACKUP"

log_msg "Stop temporary MySQL/MariaDB if running from prevent execution"

stop_mysql_temp

log_msg "Start temporary MariaDB instance on port $TMP_PORT"

mysqld_safe \
    --no-defaults \
    --datadir="$PHYSICAL_BACKUP" \
    --socket="$TMP_SOCKET" \
    --port=$TMP_PORT \
    --skip-networking=0 \
    --skip-grant-tables=0 \
    --skip-slave-start \
    --wsrep_on=OFF \
    --innodb_buffer_pool_size=512M \
    > "$BACKUP_DIR/mysqld_$DATE.log" 2>&1 &

# Attendre que MySQL soit prêt
log_msg "Waiting for MariaDB on port $TMP_PORT ..."
for i in {1..30}; do
    if mysqladmin --socket="$TMP_SOCKET" ping &>/dev/null; then
        echo " [ READY ]"
        break
    fi
    echo -n "."
    sleep 2
done

log_msg "Create directory '$LOGICAL_BACKUP'"
mkdir -p "$LOGICAL_BACKUP"


log_msg "Logical backup with mydumper"

# -t 4 => 4 threads //
mydumper --socket="$TMP_SOCKET" --outputdir="$LOGICAL_BACKUP" --routines --events --triggers --rows=50000 --compress --user=$MYSQL_USER -t 4

log_msg "Stop temporary MariaDB/MySQL"

stop_mysql_temp

log_msg "Create tar.gz archive for physical backup"


threads=$(( ( $(nproc) + 3 ) / 4 ))
# Sécurité : si threads < 1, on met à 1
if ! [[ "$threads" =~ ^[0-9]+$ ]] || [ "$threads" -lt 1 ]; then
    threads=1
fi

tar cf - -C "$BACKUP_DIR" "physical_$DATE" | pigz -p "$threads" -3 > "$ARCHIVE"

#tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "physical_$DATE"
#tar cf - "$PHYSICAL_BACKUP" | pigz -p $threads -3 > "$ARCHIVE"


log_msg "Move backups (logical & physical) to '$BACKUP_DIR_DIR'"

mv "$ARCHIVE" "$STORE_ARCHIVE"
mv "$LOGICAL_BACKUP" "$LOGICAL_SAVE"

log_msg "[SUCCESS] Backups termined"

elapsed=$SECONDS
hours=$((elapsed / 3600))
minutes=$(( (elapsed % 3600) / 60 ))
seconds=$((elapsed % 60))

physical_size=$(du -sh "$PHYSICAL_BACKUP")
logical_size=$(du -sh "$LOGICAL_SAVE")
physical_compressed=$(du -sh "$STORE_ARCHIVE")

echo "#####################################################"
echo "Backup exécuté en : ${hours}h ${minutes}m ${seconds}s"
echo "Backup physical size       : $physical_size"
echo "Backup physical compressed : $physical_compressed"
echo "Backup logical size        : $logical_size"
echo "#####################################################"

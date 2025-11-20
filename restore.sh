#!/bin/bash

set -euo pipefail

# === Variables par défaut ===
BACKUP_DIR="/srv/mysql/backup/daily"
TMP_DIR="/tmp/mysql_restore"
MYSQL_HOST="45.45.99.99"
MYSQL_USER="root"
MYSQL_PASS="DFGHQRSTHGTA"
DRYRUN=false

# === Fonction d’aide ===
usage() {
  echo "Usage: $0 [-h host] [-u user] [-p password] [--dry-run]"
  echo "  -h <host>      Hôte MySQL (par défaut: localhost)"
  echo "  -u <user>      Utilisateur MySQL (par défaut: root)"
  echo "  -p <password>  Mot de passe MySQL"
  echo "  --dry-run      Affiche les commandes sans les exécuter"
  exit 1
}

# === Parsing des arguments ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h) MYSQL_HOST="$2"; shift 2 ;;
    -u) MYSQL_USER="$2"; shift 2 ;;
    -p) MYSQL_PASS="$2"; shift 2 ;;
    --dry-run) DRYRUN=true; shift ;;
    -*) echo "Option inconnue : $1"; usage ;;
    *) usage ;;
  esac
done

MYSQL_OPTS="--host=$MYSQL_HOST --user=$MYSQL_USER"
[ -n "$MYSQL_PASS" ] && MYSQL_OPTS="$MYSQL_OPTS --password=$MYSQL_PASS"

mkdir -p "$TMP_DIR"

echo "=== Chargement des backups MySQL ==="
echo "Hôte MySQL : $MYSQL_HOST"
echo "Utilisateur : $MYSQL_USER"
echo "Répertoire : $BACKUP_DIR"
echo "Mode Dry-run : $DRYRUN"
echo

# === 1. Détection des derniers fichiers ===
echo "=== 1. Recherche des derniers fichiers dans chaque dossier ==="

latest_files=()  # reset

for dir in "$BACKUP_DIR"/*; do
    [ -d "$dir" ] || continue

    base="$(basename "$dir")"

    [[ "$(basename "$dir")" == "#mysql50#lost+found" ]] && continue
    [[ "$base" == "mysql" ]] && { echo "⏩ Dossier 'mysql' ignoré (base système)"; continue; }
    
 #   last_file=$(ls -1t "$dir"/*.sql.gz 2>/dev/null | head -n1 || true)

#upgrade en se basance sur le nom du fichier
last_file=$(
  find "$dir" -type f -name "*.sql.gz" \
  | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}h[0-9]{2}m' \
  | sort -rV \
  | head -n1 \
  | while read -r latest_date; do
      find "$dir" -type f -name "*${latest_date}*.sql.gz" | head -n1
    done
)


    if [ -n "$last_file" ]; then
        latest_files+=("$last_file")
    fi
done

# Sauvegarde dans tmp
printf "%s\n" "${latest_files[@]}" > "$TMP_DIR/latest_files.txt"

echo
echo "📁 Fichiers détectés :"
cat "$TMP_DIR/latest_files.txt" || echo "(aucun fichier trouvé)"
echo

# === 2. Extraction des coordonnées binlog ===
echo "=== 2. Extraction des coordonnées binlog ==="
rm -f "$TMP_DIR/files_with_coords.txt"

while read -r file; do
    echo "File : $file"
    [ -f "$file" ] || { echo "⚠️  Fichier inexistant : $file"; continue; }

    # Extraire la coordonnée binlog sans que le script s'arrête
coord=$(zcat "$file" 2>/dev/null | grep -m1 "CHANGE MASTER TO" | \
    sed -E "s/^--[[:space:]]*CHANGE MASTER TO.*MASTER_LOG_FILE='([^']+)', MASTER_LOG_POS=([0-9]+).*/\1 \2/" || true)


    if [ -n "$coord" ]; then
        log_file=$(echo "$coord" | awk '{print $1}')
        log_pos=$(echo "$coord" | awk '{print $2}')
        echo "Coordonnée trouvée : $log_file $log_pos"
        echo "$log_file $log_pos $file" >> "$TMP_DIR/files_with_coords.txt"
    else
        echo "⚠️  Aucune coordonnée trouvée dans $file"
    fi
done < "$TMP_DIR/latest_files.txt"

echo
echo "📄 Coordonnées trouvées :"
cat "$TMP_DIR/files_with_coords.txt" || echo "(aucune)"
echo

# === 3. Tri selon fichier binlog et position ===
echo "=== 3. Tri par MASTER_LOG_FILE et MASTER_LOG_POS ==="
sort -k1,1 -k2,2n "$TMP_DIR/files_with_coords.txt" > "$TMP_DIR/sorted_files.txt"

echo
echo "📑 Fichiers triés (ordre d’exécution) :"
cat "$TMP_DIR/sorted_files.txt" || echo "(vide)"
echo

# === 4. Traitement séquentiel ===
declare -a FILES
declare -a DBNAMES
while read -r log_file log_pos full_path; do
    FILES+=("$full_path")
    dbname=$(basename "$(dirname "$full_path")")
    DBNAMES+=("$dbname")
done < "$TMP_DIR/sorted_files.txt"

total=${#FILES[@]}
for ((i=0; i<total; i++)); do
    db="${DBNAMES[$i]}"

    # Extraire log_file, log_pos et full_path à partir du fichier trié
    read -r log_file log_pos full_path < <(awk "NR==$((i+1)){print \$1, \$2, \$3}" "$TMP_DIR/sorted_files.txt")

    # Si full_path n’est pas complet, le reconstruire proprement
    if [[ -z "$full_path" || "$full_path" != /* ]]; then
        full_path=$(awk "NR==$((i+1)){for(i=3;i<=NF;i++)printf \$i\" \";print \"\"}" "$TMP_DIR/sorted_files.txt" | xargs)
    fi

    file="$full_path"

    echo "-------------------------------------------"
    echo "💾 Étape $((i+1)) / $total"
    echo "Fichier : $file"
    echo "Base de données : $db"
    echo "Binlog : $log_file  |  Position : $log_pos"
    echo "-------------------------------------------"

if (( i == 0 )); then
        echo
        echo "➡️  Commande CHANGE MASTER TO (vers $log_file:$log_pos)"
        cmd="STOP SLAVE; CHANGE MASTER TO MASTER_LOG_FILE='$log_file', MASTER_LOG_POS=$log_pos, MASTER_SSL=0, MASTER_SSL_VERIFY_SERVER_CERT=0;"
        echo "mysql $MYSQL_OPTS -e \"$cmd\""

        if [ "$DRYRUN" = false ]; then
            mysql $MYSQL_OPTS -e "$cmd"
        fi
else
	echo
	echo "➡️  START SLAVE UNTIL (vers $log_file:$log_pos)"
	cmd="START SLAVE UNTIL MASTER_LOG_FILE='$log_file', MASTER_LOG_POS=$log_pos;"
        if [ "$DRYRUN" = false ]; then
            mysql $MYSQL_OPTS -e "$cmd"
	    sleep 3
            mysql $MYSQL_OPTS -e "SHOW SLAVE STATUS\\G" | grep Until || true
        fi
fi

echo
echo "▶️  Création de la base si nécessaire :"
echo "mysql $MYSQL_OPTS -e \"CREATE DATABASE IF NOT EXISTS \`$db\`;\""
if [ "$DRYRUN" = false ]; then
    mysql $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
fi

    echo
    echo "▶️  Commande d’import :"
    #echo "mysql $MYSQL_OPTS $db < <(zcat \"$file\")"
    echo "zcat $file | pv | mysql $MYSQL_OPTS $db"
    if [ "$DRYRUN" = false ]; then
        #zcat "$file" | mysql $MYSQL_OPTS "$db"
        zcat "$file" | pv | mysql $MYSQL_OPTS "$db"
    fi


    echo
done

# === 5. Commande finale ===
echo "=== 5. Commande finale START SLAVE ==="
echo "mysql $MYSQL_OPTS -e \"START SLAVE;\""
if [ "$DRYRUN" = false ]; then
    mysql $MYSQL_OPTS -e "START SLAVE;"
fi

echo
if [ "$DRYRUN" = true ]; then
  echo "✅ Dry-run terminé : aucune commande exécutée."
else
  echo "✅ Exécution terminée : réplication configurée."
fi


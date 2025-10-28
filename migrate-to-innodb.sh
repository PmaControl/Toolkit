#!/bin/bash
set -euo pipefail

# === Variables ===
MYSQL_HOST="localhost"
MYSQL_USER="root"
MYSQL_PASS=""
THREADS=4
DRYRUN=false
ERROR_LOG="/tmp/migrate_innodb_errors.log"
TMP_FILE="/tmp/migrate_innodb_tasks.txt"
PROGRESS_FILE="/tmp/migrate_innodb_progress.txt"
> "$ERROR_LOG"
> "$TMP_FILE"
> "$PROGRESS_FILE"

# === Couleurs ===
PURPLE="\033[1;35m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
RESET="\033[0m"

# === Fonctions ===
usage() {
  echo "Usage: $0 -h <host> -u <user> -p <password> [--dry-run] [--threads N]"
  echo "  -h <host>      Hôte MySQL (par défaut: localhost)"
  echo "  -u <user>      Utilisateur MySQL (par défaut: root)"
  echo "  -p <password>  Mot de passe MySQL"
  echo "  --threads N    Nombre de threads parallèles (défaut: 4)"
  echo "  --dry-run      Affiche les commandes sans les exécuter"
  exit 1
}

# === Parsing des arguments ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h) MYSQL_HOST="$2"; shift 2 ;;
    -u) MYSQL_USER="$2"; shift 2 ;;
    -p) MYSQL_PASS="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --dry-run) DRYRUN=true; shift ;;
    *) usage ;;
  esac
done

if [[ -z "$MYSQL_USER" || -z "$MYSQL_HOST" ]]; then
  usage
fi

START_TIME=$(date +%s)

# === Commande MySQL ===
MYSQL_CMD=(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -B -e)

# === Bases à ignorer ===
IGNORE_DATABASES="'mysql','information_schema','performance_schema','sys'"

echo -e "${YELLOW}=== Migration des tables vers InnoDB ===${RESET}"
echo "Hôte : $MYSQL_HOST"
echo "Utilisateur : $MYSQL_USER"
echo "Mode Dry-run : $DRYRUN"
echo "Threads : $THREADS"
echo

# === Construction de la liste des tables ===
DATABASES=$("${MYSQL_CMD[@]}" "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ($IGNORE_DATABASES);")

for DB in $DATABASES; do
  "${MYSQL_CMD[@]}" "
    SELECT table_name, engine
    FROM information_schema.tables
    WHERE table_schema='$DB' AND engine!='InnoDB'
    ORDER BY table_name;
  " | while read -r TABLE ENGINE; do
    echo "$DB $TABLE $ENGINE" >> "$TMP_FILE"
  done
done

TOTAL=$(wc -l < "$TMP_FILE")
if [[ $TOTAL -eq 0 ]]; then
  echo -e "${GREEN}Toutes les tables sont déjà en InnoDB 🎉${RESET}"
  exit 0
fi

MAX_WIDTH=$(awk '{print length($1 "." $2)}' "$TMP_FILE" | sort -nr | head -1)
PADDING=$((MAX_WIDTH + 60))

# === Fonction de migration ===
migrate_table() {
  local INDEX="$1" DB="$2" TABLE="$3" ENGINE="$4"
  local MYSQL_HOST="$5" MYSQL_USER="$6" MYSQL_PASS="$7"
  local DRYRUN="$8" PADDING="$9"
  local PURPLE="${10}" YELLOW="${11}" GREEN="${12}" RED="${13}" CYAN="${14}" RESET="${15}" ERROR_LOG="${16}" PROGRESS_FILE="${17}"

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  COUNT_FMT=$(printf "%05d" "$INDEX")
  ROWS_INFO=""

  # Compte les lignes uniquement pour MyISAM ou Aria
  if [[ "$ENGINE" =~ ^(MyISAM|Aria)$ ]]; then
    ROWS=$(
      mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -B -e "SELECT COUNT(1) FROM \`${DB}\`.\`${TABLE}\`;" 2>/dev/null || echo "?"
    )
    ROWS_INFO="(${CYAN}${ROWS} rows${RESET}) "
  fi

  SQL="ALTER TABLE \`${DB}\`.\`${TABLE}\` ENGINE=InnoDB;"
  LABEL="🔄 Migration de ${YELLOW}${DB}.${TABLE}${RESET} ${ROWS_INFO}..."

  if [[ "$DRYRUN" == "true" ]]; then
    printf "${PURPLE}%s${RESET} [%s] 🟡 %-*s\n" "$TIMESTAMP" "$COUNT_FMT" "$PADDING" "$SQL"
    echo 1 >> "$PROGRESS_FILE"
    return
  fi

  START_TABLE=$(date +%s)
  printf "${PURPLE}%s${RESET} [%s] %-*s" "$TIMESTAMP" "$COUNT_FMT" "$PADDING" "$LABEL"

  if ! mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -B -e "$SQL" >/dev/null 2>&1; then
    END_TABLE=$(date +%s)
    DIFF=$((END_TABLE - START_TABLE))
    H=$((DIFF/3600))
    M=$(( (DIFF%3600)/60 ))
    S=$((DIFF%60))
    printf "${RED}❌ ERREUR${RESET} (${H}h:${M}m:${S}s)\n"
    echo "${DB}.${TABLE}" >> "$ERROR_LOG"
  else
    END_TABLE=$(date +%s)
    DIFF=$((END_TABLE - START_TABLE))
    H=$((DIFF/3600))
    M=$(( (DIFF%3600)/60 ))
    S=$((DIFF%60))
    printf "${GREEN}✅ OK${RESET} (${H}h:${M}m:${S}s)\n"
  fi

  echo 1 >> "$PROGRESS_FILE"
}

export -f migrate_table
export MYSQL_HOST MYSQL_USER MYSQL_PASS DRYRUN PADDING PURPLE YELLOW GREEN RED CYAN RESET ERROR_LOG PROGRESS_FILE

# === Barre de progression ===
progress_bar() {
  local TOTAL=$1
  local PROGRESS_FILE=$2
  local WIDTH=40
  while true; do
    local DONE=$(wc -l < "$PROGRESS_FILE" | tr -d ' ')
    local PERCENT=$((100 * DONE / TOTAL))
    local FILLED=$((WIDTH * DONE / TOTAL))
    printf "\r${CYAN}[%-${WIDTH}s]${RESET} %3d%% (%d/%d)" "$(printf '#%.0s' $(seq 1 $FILLED))" "$PERCENT" "$DONE" "$TOTAL"
    if [[ $DONE -ge $TOTAL ]]; then
      break
    fi
    sleep 0.3
  done
  echo
}

# === Lancement de la barre en tâche de fond ===
progress_bar "$TOTAL" "$PROGRESS_FILE" &
BAR_PID=$!

# === Exécution parallèle ===
awk '{print NR, $1, $2, $3}' "$TMP_FILE" | parallel -j "$THREADS" --colsep ' ' \
  migrate_table {1} {2} {3} {4} "$MYSQL_HOST" "$MYSQL_USER" "$MYSQL_PASS" "$DRYRUN" "$PADDING" \
  "$PURPLE" "$YELLOW" "$GREEN" "$RED" "$CYAN" "$RESET" "$ERROR_LOG" "$PROGRESS_FILE"

wait $BAR_PID

# === Fin ===
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
H=$((ELAPSED/3600))
M=$(( (ELAPSED%3600)/60 ))
S=$((ELAPSED%60))

echo
echo -e "${YELLOW}=== Résumé ===${RESET}"
if [[ -s "$ERROR_LOG" ]]; then
  echo -e "${RED}Les tables suivantes n'ont pas pu être migrées :${RESET}"
  cat "$ERROR_LOG"
else
  echo -e "${GREEN}Aucune erreur rencontrée 🎉${RESET}"
fi

echo
echo -e "${YELLOW}⏱ Temps total d'exécution : ${PURPLE}${H}h:${M}m:${S}s${RESET}"

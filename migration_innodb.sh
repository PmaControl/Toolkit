#!/bin/bash
set -euo pipefail

# === Variables ===
MYSQL_HOST="localhost"
MYSQL_USER="root"
MYSQL_PASS=""
DRYRUN=false
ERROR_LOG="/tmp/migrate_innodb_errors.log"
> "$ERROR_LOG"

# === Fonctions ===
usage() {
  echo "Usage: $0 -h <host> -u <user> -p <password> [--dry-run]"
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
    *) usage ;;
  esac
done

# Vérification basique
if [[ -z "$MYSQL_USER" || -z "$MYSQL_HOST" ]]; then
  usage
fi

# === Commande MySQL ===
MYSQL_CMD=(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASS" -N -B -e)

# === Bases à ignorer ===
IGNORE_DATABASES="'mysql','information_schema','performance_schema','sys'"

echo "=== Migration des tables vers InnoDB ==="
echo "Hôte : $MYSQL_HOST"
echo "Utilisateur : $MYSQL_USER"
echo "Mode Dry-run : $DRYRUN"
echo

# === Liste des bases utilisateurs ===
DATABASES=$("${MYSQL_CMD[@]}" "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ($IGNORE_DATABASES);")

for DB in $DATABASES; do
  echo "📦 Base : $DB"
  
  # Récupération des tables non-InnoDB
  TABLES=$("${MYSQL_CMD[@]}" "SELECT table_name FROM information_schema.tables WHERE table_schema='$DB' AND engine!='InnoDB';")

  if [[ -z "$TABLES" ]]; then
    echo "  ✅ Aucune table à migrer"
    continue
  fi

  for TABLE in $TABLES; do
    SQL="ALTER TABLE \`$DB\`.\`$TABLE\` ENGINE=InnoDB;"
    if $DRYRUN; then
      echo "  🟡 $SQL"
    else
      echo -n "  🔄 Migration de $DB.$TABLE ... "
      if ! "${MYSQL_CMD[@]}" "$SQL" >/dev/null 2>&1; then
        echo "❌ ERREUR"
        echo "$DB.$TABLE" >> "$ERROR_LOG"
      else
        echo "✅ OK"
      fi
    fi
  done
done

echo
echo "=== Résumé des erreurs ==="
if [[ -s "$ERROR_LOG" ]]; then
  echo "Les tables suivantes n'ont pas pu être migrées :"
  cat "$ERROR_LOG"
else
  echo "Aucune erreur rencontrée 🎉"
fi

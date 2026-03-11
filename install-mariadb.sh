#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

VERSION='11.4'
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
DEBIAN_PASSWORD="$(date +%s | sha256sum | base64 | head -c 32; echo)"
IP_PMACONTROL='localhost'
ADD_TO_PMACONTROL='false'
PMA_PARAM=''
PROXY_OVERRIDE=''
PMACONTROL_PASSWORD=''

SUPPORTED_DISTRIBUTIONS=('debian' 'ubuntu')
SUPPORTED_CODENAMES=('bookworm' 'trixie' 'noble')
DEFAULT_MYSQL_DATADIR='/var/lib/mysql'
MANAGED_CONFIG_NAME='90-pmacontrol.cnf'

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date '+%F %T')" "$*" >&2
}

fatal() {
  printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: ./install-mariadb.sh -p PASSWORD [options]

Options:
  -h                Show help
  -p PASSWORD       Root password for MariaDB
  -n NAME           Galera cluster name (default: ${CLUSTER_NAME})
  -m IP1,IP2,...    Galera cluster member list
  -v VERSION        MariaDB version (default: ${VERSION})
  -c                Enable Galera configuration
  -u                Purge previous MySQL/MariaDB packages before install
  -d PATH           Datadir root (default: ${DATADIR})
  -r                Use local repository configuration instead of MariaDB repo setup
  -b                Bootstrap a new Galera cluster
  -x PASSWORD       Password for debian-sys-maint
  -y PROXY          Override HTTP/HTTPS proxy
  -a IP,USER,PASS   Add grants for a PmaControl server
USAGE
}

parse_args() {
  while getopts 'hp:n:m:v:cud:rbx:y:a:' flag; do
    case "${flag}" in
      h) usage; exit 0 ;;
      p) PASSWORD="${OPTARG}" ;;
      n) CLUSTER_NAME="${OPTARG}" ;;
      m) CLUSTER_MEMBER="${OPTARG}" ;;
      v) VERSION="${OPTARG}" ;;
      c) CLUSTER='ON' ;;
      u) PURGE='true' ;;
      d) DATADIR="${OPTARG}" ;;
      r) REPO_LOCAL='true' ;;
      b) BOOTSTRAP='true' ;;
      x) DEBIAN_PASSWORD="${OPTARG}" ;;
      y) PROXY_OVERRIDE="${OPTARG}" ;;
      a) ADD_TO_PMACONTROL='true'; PMA_PARAM="${OPTARG}" ;;
      *) usage; exit 1 ;;
    esac
  done

  [[ -n "${PASSWORD}" ]] || fatal 'Option -p PASSWORD is required.'
  [[ -n "${VERSION}" ]] || VERSION='11.4'
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fatal 'This script must run as root.'
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_proxy() {
  if [[ -n "${PROXY_OVERRIDE}" ]]; then
    printf '%s\n' "${PROXY_OVERRIDE}"
    return
  fi

  if compgen -G '/etc/apt/apt.conf.d/*' >/dev/null; then
    awk -F'"' '/Acquire::https::proxy|Acquire::http::proxy/ {print $2; exit}' /etc/apt/apt.conf.d/* 2>/dev/null || true
  fi
}

configure_proxy() {
  local proxy
  proxy="$(get_proxy || true)"
  if [[ -n "${proxy}" ]]; then
    export http_proxy="${proxy}"
    export https_proxy="${proxy}"
    log "Proxy detected and exported."
  fi
}

detect_platform() {
  local distrib codename

  command_exists lsb_release || { apt-get update -y >/dev/null; apt-get install -y lsb-release >/dev/null; }

  distrib="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
  codename="$(lsb_release -sc | tr '[:upper:]' '[:lower:]')"

  printf '%s\n' "${SUPPORTED_DISTRIBUTIONS[@]}" | grep -qx "${distrib}" || fatal "Unsupported distribution: ${distrib}"
  printf '%s\n' "${SUPPORTED_CODENAMES[@]}" | grep -qx "${codename}" || fatal "Unsupported release: ${codename}. Supported: Debian 12/13 and Ubuntu 24.04."

  DISTRIB="${distrib}"
  OS_CODENAME="${codename}"
  log "Detected platform: ${DISTRIB} ${OS_CODENAME}"
}

apt_install() {
  local packages=()
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q 'install ok installed'; then
      packages+=("${pkg}")
    fi
  done

  if ((${#packages[@]} > 0)); then
    apt-get install -y "${packages[@]}"
  fi
}

apt_install_optional() {
  local pkg
  for pkg in "$@"; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      apt_install "${pkg}"
    else
      warn "Optional package not available on this platform: ${pkg}"
    fi
  done
}

setup_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt_install ca-certificates curl gnupg2 lsb-release bc coreutils mawk procps rsync apt-transport-https openssl wget tar socat lsof vim tree locate screen iftop htop git unzip atop nmap
}

purge_existing_install() {
  local packages=()
  mapfile -t packages < <(dpkg-query -W -f='${binary:Package}\n' 'mariadb*' 'mysql*' 'percona*' 2>/dev/null | sort -u || true)

  if ((${#packages[@]} > 0)); then
    log 'Purging existing MySQL/MariaDB/Percona packages.'
    apt-get purge -y "${packages[@]}"
    apt-get autoremove -y
    apt-get clean
  fi
}

setup_mariadb_repository() {
  if [[ "${REPO_LOCAL}" == 'true' ]]; then
    log 'Using existing/local APT repositories.'
    return
  fi

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://mariadb.org/mariadb_release_signing_key.asc -o /etc/apt/keyrings/mariadb.asc
  cat > /etc/apt/sources.list.d/mariadb.list <<EOF_REPO
deb [signed-by=/etc/apt/keyrings/mariadb.asc] https://dlm.mariadb.com/repo/mariadb-server/${VERSION}/repo/${DISTRIB} ${OS_CODENAME} main
EOF_REPO
  apt-get update -y
}

setup_mydumper_repository() {
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1D357EA7D10C9320371BDD0279EA15C0E82E34BA&exact=on' \
    -o /etc/apt/keyrings/mydumper.asc
  cat > /etc/apt/sources.list.d/mydumper.list <<EOF_MYDUMPER
deb [signed-by=/etc/apt/keyrings/mydumper.asc] https://mydumper.github.io/mydumper/repo/apt/debian ${OS_CODENAME} main
EOF_MYDUMPER
  apt-get update -y
}

install_mariadb_packages() {
  local packages=(mariadb-client mariadb-server mariadb-backup)
  if [[ "${CLUSTER}" == 'ON' ]]; then
    packages+=(galera-4 rsync socat)
  fi
  apt_install "${packages[@]}"
}

mysql_service_name() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^mariadb\.service'; then
    printf 'mariadb\n'
  else
    printf 'mysql\n'
  fi
}

SERVICE_NAME=''

stop_mysql_service() {
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    systemctl stop "${SERVICE_NAME}"
  fi
}

start_mysql_service() {
  if [[ "${CLUSTER}" == 'ON' && "${BOOTSTRAP}" == 'true' ]]; then
    command_exists galera_new_cluster || fatal 'galera_new_cluster command not found.'
    galera_new_cluster
  else
    systemctl restart "${SERVICE_NAME}"
  fi
}

wait_for_mysql() {
  local timeout=60
  local client_bin='mariadb-admin'
  command_exists mariadb-admin || client_bin='mysqladmin'

  while ((timeout > 0)); do
    if "${client_bin}" --defaults-file=/root/.my.cnf ping >/dev/null 2>&1; then
      return 0
    fi
    if mariadb --protocol=socket -uroot -e 'SELECT 1' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    timeout=$((timeout - 1))
  done

  systemctl status "${SERVICE_NAME}" --no-pager || true
  fatal 'MariaDB did not become ready in time.'
}

bytes_from_mib() {
  awk -v mib="$1" 'BEGIN { printf "%.0f", mib * 1024 * 1024 }'
}

round_down_to_chunk_mib() {
  local value="$1"
  local chunk="$2"
  awk -v value="${value}" -v chunk="${chunk}" 'BEGIN { printf "%d", int(value / chunk) * chunk }'
}

compute_tuning() {
  local mem_mib cores buffer_pool_mib tmp_table_bytes max_connections thread_pool_size
  local io_threads purge_threads free_bytes desired_log_bytes free_probe_path

  mem_mib="$(awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo)"
  cores="$(nproc --all)"

  if (( mem_mib <= 3072 )); then
    buffer_pool_mib=1024
  elif (( mem_mib <= 8192 )); then
    buffer_pool_mib=$(( mem_mib * 40 / 100 ))
  elif (( mem_mib <= 16384 )); then
    buffer_pool_mib=$(( mem_mib * 50 / 100 ))
  else
    buffer_pool_mib=$(( mem_mib * 58 / 100 ))
  fi

  if (( buffer_pool_mib > mem_mib - 1024 )); then
    buffer_pool_mib=$(( mem_mib - 1024 ))
  fi
  if (( buffer_pool_mib < 1024 )); then
    buffer_pool_mib=1024
  fi
  buffer_pool_mib="$(round_down_to_chunk_mib "${buffer_pool_mib}" 128)"

  if (( mem_mib >= 16384 )); then
    tmp_table_bytes=1073741824
  else
    tmp_table_bytes=805306368
  fi

  if (( mem_mib >= 16384 && cores >= 8 )); then
    max_connections=120
  else
    max_connections=100
  fi

  if (( cores >= 8 )); then
    thread_pool_size=8
  elif (( cores >= 4 )); then
    thread_pool_size=4
  else
    thread_pool_size=2
  fi

  if (( cores >= 16 )); then
    io_threads=8
  else
    io_threads=4
  fi

  if (( cores >= 8 )); then
    purge_threads=4
  elif (( cores >= 4 )); then
    purge_threads=2
  else
    purge_threads=1
  fi

  TUNE_INNODB_CHANGE_BUFFERING='none'
  TUNE_INNODB_ADAPTIVE_FLUSHING_LWM='10'
  TUNE_INNODB_MAX_DIRTY_PAGES_PCT='70'
  TUNE_INNODB_AUTOEXTEND_INCREMENT='1000'
  TUNE_THREAD_STACK='524288'
  TUNE_TRANSACTION_PREALLOC_SIZE='8192'
  TUNE_THREAD_CACHE_SIZE='100'
  TUNE_MAX_CONNECTIONS="${max_connections}"
  TUNE_QUERY_CACHE_TYPE='0'
  TUNE_QUERY_CACHE_SIZE='0'
  TUNE_QUERY_CACHE_LIMIT='131072'
  TUNE_QUERY_CACHE_MIN_RES_UNIT='4096'
  TUNE_KEY_BUFFER_SIZE='134217728'
  TUNE_MAX_HEAP_TABLE_SIZE="${tmp_table_bytes}"
  TUNE_TMP_TABLE_SIZE="${tmp_table_bytes}"
  TUNE_INNODB_BUFFER_POOL_SIZE="$(bytes_from_mib "${buffer_pool_mib}")"
  free_probe_path="$(effective_data_dir)"
  if [[ ! -e "${free_probe_path}" ]]; then
    free_probe_path="$(dirname "${free_probe_path}")"
  fi
  free_bytes="$(df -B1 "${free_probe_path}" | awk 'END {print $4}')"
  desired_log_bytes='994050048'
  if [[ -n "${free_bytes}" ]] && (( free_bytes > 0 )); then
    if (( free_bytes < 2147483648 )); then
      desired_log_bytes='268435456'
    elif (( free_bytes < 4294967296 )); then
      desired_log_bytes='536870912'
    fi
  fi
  TUNE_INNODB_LOG_FILE_SIZE="${desired_log_bytes}"
  TUNE_INNODB_FILE_PER_TABLE='1'
  TUNE_SORT_BUFFER_SIZE='33554432'
  TUNE_READ_RND_BUFFER_SIZE='1048576'
  TUNE_BULK_INSERT_BUFFER_SIZE='16777216'
  TUNE_MYISAM_SORT_BUFFER_SIZE='536870912'
  TUNE_INNODB_BUFFER_POOL_CHUNK_SIZE='0'
  TUNE_JOIN_BUFFER_SIZE='262144'
  TUNE_TABLE_OPEN_CACHE='10000'
  TUNE_TABLE_DEFINITION_CACHE='10000'
  TUNE_INNODB_FLUSH_LOG_AT_TRX_COMMIT='2'
  TUNE_INNODB_LOG_BUFFER_SIZE='8388608'
  TUNE_INNODB_WRITE_IO_THREADS="${io_threads}"
  TUNE_INNODB_READ_IO_THREADS="${io_threads}"
  TUNE_INNODB_FLUSH_METHOD='O_DIRECT'
  TUNE_OPTIMIZER_SEARCH_DEPTH='62'
  TUNE_INNODB_PURGE_THREADS="${purge_threads}"
  TUNE_THREAD_HANDLING='one-thread-per-connection'
  TUNE_THREAD_POOL_SIZE="${thread_pool_size}"
  TUNE_INNODB_LOG_FILE_BUFFERING='1'
  TUNE_PERFORMANCE_SCHEMA_MAX_SQL_TEXT_LENGTH='1024'
  TUNE_MAX_DIGEST_LENGTH='1024'
  TUNE_PERFORMANCE_SCHEMA_MAX_DIGEST_LENGTH='1024'
  TUNE_PERFORMANCE_SCHEMA_DIGESTS_SIZE='5000'
  TUNE_PERFORMANCE_SCHEMA_EVENTS_STATEMENTS_HISTORY_SIZE='50'
  TUNE_OPEN_FILES_LIMIT='32768'
}

get_primary_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

compute_server_id() {
  local primary_ip
  primary_ip="$(get_primary_ip)"
  [[ -n "${primary_ip}" ]] || primary_ip='127.0.0.1'
  cksum <<<"${primary_ip}" | awk '{print $1}'
}

effective_data_dir() {
  if [[ "${DATADIR%/}" == "${DEFAULT_MYSQL_DATADIR}" ]]; then
    printf '%s\n' "${DEFAULT_MYSQL_DATADIR}"
  else
    printf '%s\n' "${DATADIR}/data"
  fi
}

effective_tmp_dir() {
  if [[ "${DATADIR%/}" == "${DEFAULT_MYSQL_DATADIR}" ]]; then
    printf '/var/tmp/mysql\n'
  else
    printf '%s\n' "${DATADIR}/tmp"
  fi
}

ensure_datadir_layout() {
  install -d -o mysql -g mysql -m 0750 \
    "${DATADIR}" \
    "${DATADIR}/backup" \
    "${DATADIR}/binlog" \
    "$(effective_data_dir)" \
    "${DATADIR}/log" \
    "${DATADIR}/relaylog" \
    "$(effective_tmp_dir)"
}

initialize_datadir_if_needed() {
  local target_data_dir
  target_data_dir="$(effective_data_dir)"

  if [[ -d "${target_data_dir}/mysql" ]]; then
    return
  fi

  log "Initializing MariaDB system tables in ${target_data_dir}"
  mariadb-install-db \
    --auth-root-authentication-method=normal \
    --user=mysql \
    --basedir=/usr \
    --datadir="${target_data_dir}" \
    --skip-test-db >/dev/null
}

current_mysql_datadir() {
  local detected
  detected="$(mysqld --verbose --help 2>/dev/null | awk '$1 == "datadir" {print $2; exit}' || true)"
  if [[ -z "${detected}" ]]; then
    detected="${DEFAULT_MYSQL_DATADIR}/"
  fi
  printf '%s\n' "${detected%/}"
}

migrate_datadir_if_needed() {
  local source_datadir target_data_dir
  source_datadir="$(current_mysql_datadir)"
  target_data_dir="$(effective_data_dir)"

  ensure_datadir_layout

  if [[ "${target_data_dir%/}" == "${source_datadir%/}" ]]; then
    log 'Datadir unchanged, no migration required.'
    return
  fi

  if [[ -d "${target_data_dir}/mysql" ]]; then
    log 'Target datadir already initialized, skipping data copy.'
    return
  fi

  if [[ -d "${source_datadir}/mysql" ]]; then
    log "Migrating data from ${source_datadir} to ${target_data_dir}"
    rsync -aHAX --delete "${source_datadir}/" "${target_data_dir}/"
    chown -R mysql:mysql "${DATADIR}"
  else
    log 'No existing datadir detected to migrate.'
  fi
}

configure_apparmor() {
  local profile='' local_file=''

  for profile in /etc/apparmor.d/usr.sbin.mariadbd /etc/apparmor.d/usr.sbin.mysqld; do
    [[ -f "${profile}" ]] || continue
    local_file="/etc/apparmor.d/local/$(basename "${profile}")"
    install -d /etc/apparmor.d/local
    touch "${local_file}"
    if ! grep -Fq "${DATADIR}/ r," "${local_file}" 2>/dev/null; then
      cat >> "${local_file}" <<APPARMOR
${DATADIR}/ r,
${DATADIR}/** rwk,
APPARMOR
    fi
  done

  if systemctl list-unit-files 2>/dev/null | grep -q '^apparmor\.service'; then
    systemctl reload apparmor || systemctl restart apparmor || true
  fi
}

managed_config_path() {
  if [[ -d /etc/mysql/mariadb.conf.d ]]; then
    printf '/etc/mysql/mariadb.conf.d/%s\n' "${MANAGED_CONFIG_NAME}"
  else
    printf '/etc/mysql/conf.d/%s\n' "${MANAGED_CONFIG_NAME}"
  fi
}

write_managed_config() {
  local config_file primary_ip server_id hostname_short galera_block=''
  local audit_block=''
  local data_dir tmp_dir
  config_file="$(managed_config_path)"
  primary_ip="$(get_primary_ip)"
  server_id="$(compute_server_id)"
  hostname_short="$(hostname -s)"
  data_dir="$(effective_data_dir)"
  tmp_dir="$(effective_tmp_dir)"

  if [[ -f /usr/lib/mysql/plugin/server_audit.so || -f /usr/lib64/mysql/plugin/server_audit.so ]]; then
    audit_block=$(cat <<AUDIT
plugin-load-add=server_audit
server_audit_logging=1
server_audit=FORCE_PLUS_PERMANENT
server_audit_events=CONNECT,QUERY_DDL
server_audit_output_type=FILE
server_audit_file_path=${DATADIR}/log/audit.log
server_audit_file_rotate_size=1000000
server_audit_file_rotations=9
AUDIT
)
  else
    warn 'server_audit plugin not found on this platform, skipping audit plugin activation.'
  fi

  if [[ "${CLUSTER}" == 'ON' ]]; then
    galera_block=$(cat <<GALERA
[galera]
wsrep_on=ON
wsrep_cluster_name=${CLUSTER_NAME}
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_address=gcomm://${CLUSTER_MEMBER}
wsrep_node_address=${primary_ip}
wsrep_node_name=${hostname_short}
wsrep_gtid_mode=ON
wsrep_sst_method=xtrabackup-v2
wsrep_sst_auth=sst:QSEDWGRg133
wsrep_provider_options=gcache.size=20G
binlog_format=ROW
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0
wsrep_slave_threads=${TUNE_INNODB_READ_IO_THREADS}
wsrep_certify_nonPK=1
wsrep_max_ws_rows=131072
wsrep_max_ws_size=1073741824
wsrep_debug=0
wsrep_convert_LOCK_to_trx=0
wsrep_retry_autocommit=1
wsrep_auto_increment_control=1
wsrep_drupal_282555_workaround=0
wsrep_causal_reads=0
wsrep_log_conflicts=1
GALERA
)
  fi

  cat > "${config_file}" <<EOF_CONF
# Managed by PmaControl Toolkit install-mariadb.sh
# Re-running the installer is expected and should converge to this state.

[client]
port=3306
socket=/var/run/mysqld/mysqld.sock

[mysqld_safe]
socket=/var/run/mysqld/mysqld.sock
nice=0

[mysqld]
user=mysql
pid-file=/var/run/mysqld/mysqld.pid
socket=/var/run/mysqld/mysqld.sock
port=3306
basedir=/usr
datadir=${data_dir}
tmpdir=${tmp_dir}
lc_messages_dir=/usr/share/mysql
lc_messages=en_US
plugin_dir=/usr/lib/mysql/plugin/
skip-name-resolve

character-set-server=utf8mb4
collation-server=utf8mb4_general_ci
sql_mode=NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
performance_schema=ON
connect_timeout=10
wait_timeout=18000
innodb_rollback_on_timeout=1
innodb_strict_mode=0
default_storage_engine=InnoDB
event_scheduler=ON
max_allowed_packet=256M
log_error=${DATADIR}/log/error.log
general_log_file=${DATADIR}/log/general.log
slow_query_log=1
slow_query_log_file=${DATADIR}/log/mariadb-slow.log
long_query_time=1
log_slow_verbosity=query_plan
log_slave_updates=1
log_warnings=2
server-id=${server_id}
report_host=${hostname_short}
log_bin=${DATADIR}/binlog/mariadb-bin
log_bin_index=${DATADIR}/binlog/mariadb-bin.index
expire_logs_days=10
max_binlog_size=100M
relay_log=${DATADIR}/relaylog/relay-bin
relay_log_index=${DATADIR}/relaylog/relay-bin.index
relay_log_info_file=${DATADIR}/relaylog/relay-bin.info

${audit_block}

innodb_adaptive_flushing_lwm=${TUNE_INNODB_ADAPTIVE_FLUSHING_LWM}
innodb_max_dirty_pages_pct=${TUNE_INNODB_MAX_DIRTY_PAGES_PCT}
innodb_autoextend_increment=${TUNE_INNODB_AUTOEXTEND_INCREMENT}
thread_stack=${TUNE_THREAD_STACK}
transaction_prealloc_size=${TUNE_TRANSACTION_PREALLOC_SIZE}
thread_cache_size=${TUNE_THREAD_CACHE_SIZE}
max_connections=${TUNE_MAX_CONNECTIONS}
query_cache_type=${TUNE_QUERY_CACHE_TYPE}
query_cache_size=${TUNE_QUERY_CACHE_SIZE}
query_cache_limit=${TUNE_QUERY_CACHE_LIMIT}
query_cache_min_res_unit=${TUNE_QUERY_CACHE_MIN_RES_UNIT}
key_buffer_size=${TUNE_KEY_BUFFER_SIZE}
max_heap_table_size=${TUNE_MAX_HEAP_TABLE_SIZE}
tmp_table_size=${TUNE_TMP_TABLE_SIZE}
innodb_buffer_pool_size=${TUNE_INNODB_BUFFER_POOL_SIZE}
innodb_log_file_size=${TUNE_INNODB_LOG_FILE_SIZE}
innodb_file_per_table=${TUNE_INNODB_FILE_PER_TABLE}
sort_buffer_size=${TUNE_SORT_BUFFER_SIZE}
read_rnd_buffer_size=${TUNE_READ_RND_BUFFER_SIZE}
bulk_insert_buffer_size=${TUNE_BULK_INSERT_BUFFER_SIZE}
myisam_sort_buffer_size=${TUNE_MYISAM_SORT_BUFFER_SIZE}
loose-innodb_change_buffering=${TUNE_INNODB_CHANGE_BUFFERING}
loose-innodb_buffer_pool_chunk_size=${TUNE_INNODB_BUFFER_POOL_CHUNK_SIZE}
join_buffer_size=${TUNE_JOIN_BUFFER_SIZE}
table_open_cache=${TUNE_TABLE_OPEN_CACHE}
table_definition_cache=${TUNE_TABLE_DEFINITION_CACHE}
innodb_flush_log_at_trx_commit=${TUNE_INNODB_FLUSH_LOG_AT_TRX_COMMIT}
innodb_log_buffer_size=${TUNE_INNODB_LOG_BUFFER_SIZE}
innodb_write_io_threads=${TUNE_INNODB_WRITE_IO_THREADS}
innodb_read_io_threads=${TUNE_INNODB_READ_IO_THREADS}
innodb_flush_method=${TUNE_INNODB_FLUSH_METHOD}
optimizer_search_depth=${TUNE_OPTIMIZER_SEARCH_DEPTH}
innodb_purge_threads=${TUNE_INNODB_PURGE_THREADS}
thread_handling=${TUNE_THREAD_HANDLING}
loose-thread_pool_size=${TUNE_THREAD_POOL_SIZE}
loose-innodb_log_file_buffering=${TUNE_INNODB_LOG_FILE_BUFFERING}
performance_schema_max_sql_text_length=${TUNE_PERFORMANCE_SCHEMA_MAX_SQL_TEXT_LENGTH}
max_digest_length=${TUNE_MAX_DIGEST_LENGTH}
performance_schema_max_digest_length=${TUNE_PERFORMANCE_SCHEMA_MAX_DIGEST_LENGTH}
performance_schema_digests_size=${TUNE_PERFORMANCE_SCHEMA_DIGESTS_SIZE}
performance_schema_events_statements_history_size=${TUNE_PERFORMANCE_SCHEMA_EVENTS_STATEMENTS_HISTORY_SIZE}
open-files-limit=${TUNE_OPEN_FILES_LIMIT}
innodb_open_files=400
innodb_io_capacity=2000
myisam_recover_options=BACKUP
concurrent_insert=2
read_buffer_size=2M
key_cache_segments=64

[xtrabackup]
user=sst
password=QSEDWGRg133
databases-exclude=lost+found

[mysqldump]
quick
quote-names
max_allowed_packet=256M

[mysql]
no-auto-rehash

[isamchk]
key_buffer=16M

${galera_block}
EOF_CONF
}

write_root_my_cnf() {
  install -m 0600 /dev/null /root/.my.cnf
  cat > /root/.my.cnf <<EOF_ROOT
[client]
user=root
password=${PASSWORD}
socket=/var/run/mysqld/mysqld.sock
EOF_ROOT
  chmod 0600 /root/.my.cnf
}

mysql_password_ready() {
  mariadb --defaults-file=/root/.my.cnf -e 'SELECT 1' >/dev/null 2>&1
}

mysql_socket_ready() {
  mariadb --protocol=socket -uroot -e 'SELECT 1' >/dev/null 2>&1
}

mysql_exec_socket() {
  mariadb --protocol=socket -uroot -e "$1"
}

mysql_exec_password() {
  mariadb --defaults-file=/root/.my.cnf -e "$1"
}

mysql_exec() {
  if mysql_password_ready; then
    mysql_exec_password "$1"
    return
  fi
  mysql_exec_socket "$1"
}

ensure_root_password() {
  if mysql_socket_ready; then
    mysql_exec_socket "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${PASSWORD}';"
    mysql_exec_socket "ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASSWORD}';"
    mysql_exec_socket "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  elif mysql_password_ready; then
    mysql_exec_password "CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${PASSWORD}';"
    mysql_exec_password "ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASSWORD}';"
    mysql_exec_password "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  else
    fatal 'Unable to authenticate as MariaDB root user.'
  fi
  write_root_my_cnf
}

ensure_sql_accounts() {
  local server pmacontrol_ip pmacontrol_user provided_password

  mysql_exec "CREATE USER IF NOT EXISTS 'debian-sys-maint'@'localhost' IDENTIFIED BY '${DEBIAN_PASSWORD}';"
  mysql_exec "ALTER USER 'debian-sys-maint'@'localhost' IDENTIFIED BY '${DEBIAN_PASSWORD}';"
  mysql_exec "GRANT ALL PRIVILEGES ON *.* TO 'debian-sys-maint'@'localhost' WITH GRANT OPTION;"

  mysql_exec "CREATE USER IF NOT EXISTS 'sst'@'localhost' IDENTIFIED BY 'QSEDWGRg133';"
  mysql_exec "ALTER USER 'sst'@'localhost' IDENTIFIED BY 'QSEDWGRg133';"
  mysql_exec "GRANT ALL PRIVILEGES ON *.* TO 'sst'@'localhost' WITH GRANT OPTION;"

  if [[ -n "${CLUSTER_MEMBER}" ]]; then
    IFS=',' read -r -a members <<< "${CLUSTER_MEMBER}"
    for server in "${members[@]}"; do
      [[ -n "${server}" ]] || continue
      mysql_exec "CREATE USER IF NOT EXISTS 'sst'@'${server}' IDENTIFIED BY 'QSEDWGRg133';"
      mysql_exec "ALTER USER 'sst'@'${server}' IDENTIFIED BY 'QSEDWGRg133';"
      mysql_exec "GRANT ALL PRIVILEGES ON *.* TO 'sst'@'${server}' WITH GRANT OPTION;"
    done
  fi

  if [[ "${ADD_TO_PMACONTROL}" == 'true' ]]; then
    pmacontrol_ip="$(echo "${PMA_PARAM}" | cut -d',' -f1)"
    pmacontrol_user="$(echo "${PMA_PARAM}" | cut -d',' -f2)"
    provided_password="$(echo "${PMA_PARAM}" | cut -d',' -f3)"
    PMACONTROL_PASSWORD="${provided_password}"
    if [[ -n "${pmacontrol_ip}" && -n "${pmacontrol_user}" && -n "${provided_password}" ]]; then
      mysql_exec "CREATE USER IF NOT EXISTS '${pmacontrol_user}'@'${pmacontrol_ip}' IDENTIFIED BY '${provided_password}';"
      mysql_exec "ALTER USER '${pmacontrol_user}'@'${pmacontrol_ip}' IDENTIFIED BY '${provided_password}';"
      mysql_exec "GRANT ALL PRIVILEGES ON *.* TO '${pmacontrol_user}'@'${pmacontrol_ip}' WITH GRANT OPTION;"
    fi
  fi

  mysql_exec 'FLUSH PRIVILEGES;'
}

write_debian_cnf() {
  cat > /etc/mysql/debian.cnf <<EOF_DEBIAN
# Automatically generated for Debian scripts. DO NOT TOUCH!
# Managed by PmaControl Toolkit.
[client]
host     = localhost
user     = debian-sys-maint
password = ${DEBIAN_PASSWORD}
socket   = /var/run/mysqld/mysqld.sock
[mysql_upgrade]
host     = localhost
user     = debian-sys-maint
password = ${DEBIAN_PASSWORD}
socket   = /var/run/mysqld/mysqld.sock
basedir  = /usr
EOF_DEBIAN
  chmod 0600 /etc/mysql/debian.cnf
}

configure_swappiness() {
  cat > /etc/sysctl.d/99-pmacontrol-mariadb.conf <<'EOF_SYSCTL'
vm.swappiness = 1
EOF_SYSCTL
  sysctl -w vm.swappiness=1 >/dev/null
  sysctl --system >/dev/null 2>&1 || true
}

load_timezones() {
  mysql_tzinfo_to_sql /usr/share/zoneinfo | mariadb --defaults-file=/root/.my.cnf mysql >/dev/null 2>&1 || warn 'Timezone tables import skipped.'
}

run_mariadb_upgrade() {
  if command_exists mariadb-upgrade; then
    mariadb-upgrade --defaults-file=/root/.my.cnf --force >/dev/null 2>&1 || warn 'mariadb-upgrade reported a warning.'
  fi
}

print_tuning_summary() {
  log "Computed tuning: cores=$(nproc --all), innodb_buffer_pool_size=${TUNE_INNODB_BUFFER_POOL_SIZE}, max_connections=${TUNE_MAX_CONNECTIONS}, tmp_table_size=${TUNE_TMP_TABLE_SIZE}, thread_pool_size=${TUNE_THREAD_POOL_SIZE}"
}

main() {
  parse_args "$@"
  require_root
  configure_proxy
  detect_platform

  if [[ "${PURGE}" == 'true' ]]; then
    purge_existing_install
  fi

  setup_base_packages
  setup_mariadb_repository
  setup_mydumper_repository
  install_mariadb_packages
  apt_install_optional mydumper

  SERVICE_NAME="$(mysql_service_name)"

  stop_mysql_service
  compute_tuning
  print_tuning_summary
  migrate_datadir_if_needed
  initialize_datadir_if_needed
  configure_apparmor
  write_managed_config
  start_mysql_service
  wait_for_mysql
  ensure_root_password
  ensure_sql_accounts
  write_debian_cnf
  configure_swappiness
  run_mariadb_upgrade
  load_timezones

  log 'MariaDB installation/update completed successfully.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

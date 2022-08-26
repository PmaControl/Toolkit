#!/bin/bash

set -e

function cleanup()
{
  exit 1
}

function ctrl_c() {
  echo ""
  echo -ne "*** Trapped CTRL-C ***\\033[K\n"
  echo -ne "\\r...........................................................................[ ${COLOR_ERROR}✘${NC} ]${CLEAR_LINE}"
  diplay_log
  exit 1
}

spinner()
{
    trap ctrl_c INT

    local MSG=$1
    COMMAND=$2
    local COLOR_DATE='\033[0;35m'
    local COLOR_ERROR='\033[0;31m'
    local COLOR_SUCCESS='\033[0;32m'
    local COLOR_SECONDS='\033[0;33m'
    local BOLD=$(tput bold)
    local NORMAL=$(tput sgr0)
    local NC='\033[0m'
    local FRAME=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local FRAME_INTERVAL=0.1
    local CLEAR_LINE="\\033[K"

    LOG_GENERAL=$(mktemp)
    LOG_ERROR=$(mktemp)
    ERROR_CODE=$(mktemp)

    ($2 > ${LOG_GENERAL} 2> ${LOG_ERROR} ; echo $? > ${ERROR_CODE}) &
    pid=$!


    date=$(date '+%Y-%m-%d %H:%M:%S')
    START=$SECONDS
    #sleep $FRAME_INTERVAL

    modulo=${#FRAME[@]}

    i=0
    while ps -p $pid &>/dev/null; do
      #echo -ne "\\r[                 ] ${MSG} ..."

      item=$(($i % ${modulo}))

     # for k in "${!FRAME[@]}"; do
        OFFEST=$((SECONDS-START))
        echo -ne "\\r...........................................................................${BOLD}[ ${FRAME[item]} ]${NC}${CLEAR_LINE}"
        echo -ne "\\r${BOLD}[                 ] ${MSG} ...${NORMAL}"
        echo -ne "\\r${BOLD}[ ${COLOR_SECONDS}$OFFEST sec${NORMAL}"
        sleep $FRAME_INTERVAL
     # done

      i=$((i+1))
    done

    error_code=$(cat ${ERROR_CODE})
  
    if [[ "${error_code}" -eq 0 ]]; then

      if [[ -z "${error_code}" ]]; then
        diplay_log
        exit 1
      fi
      echo -ne "\\r...........................................................................[ ${COLOR_SUCCESS}✔${NC} ]${CLEAR_LINE}"
      echo -ne "\\r${COLOR_DATE}${date}${NC} ${MSG} \\n"
      #diplay_log
    else
      echo -ne "\\r...........................................................................[ ${COLOR_ERROR}✘${NC} ]${CLEAR_LINE}"
      diplay_log
      exit 1
    fi

    trap cleanup INT
}

diplay_log()
{
  error_code=$(cat ${ERROR_CODE})
  error=$(cat ${LOG_ERROR})
  log=$(cat ${LOG_GENERAL})
  local underline="\033[4m"
  local reset="\033[0m"
  local dim="\e[2m"

  running='(not running)'
  if ps -p ${pid} > /dev/null
  then
    running='(currently running...)'
  fi

  
  echo -ne "\\r${BOLD}[                 ] ${MSG} ${NORMAL}"
  echo -ne "\\r${COLOR_DATE}${date}${NC}\\n"
  echo ""
  echo ""
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}command   :${reset}${NORMAL} ${COMMAND}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}pid       :${reset}${NORMAL} ${pid} ${running}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}error     :${reset}${NORMAL} ${error_code}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}log error :${reset}${NORMAL}\n${dim}${error}${reset}\n"
  echo "--------------------------------------------------------------------------------"
  echo -ne "${BOLD}${underline}log       :${reset}${NORMAL}\n${dim}${log}${reset}\n"
  echo "--------------------------------------------------------------------------------"
}

progressbar()
{
  local BAR_SIZE="######################################################"
  local MAX_BAR_SIZE="${#BAR_SIZE}"
  local CLEAR_LINE="\\033[K"

  #pour eviter un double affichage de la bare en cas de commande très rapide
  echo -ne "${CLEAR_LINE}"

  MAX_STEPS=$1

  set +u
  if [[ -n "${STEP}" ]]; then
    STEP=$((STEP+1))
  else
    STEP=1
  fi
  set -u

  # pour eviter les bug d'affichage en cas d'erreur utilisateur
  if [[ $STEP -gt $MAX_STEPS ]]; then
    MAX_STEPS=${STEP}
  fi
  
  perc=$(((STEP) * 100 / MAX_STEPS))
  percBar=$((perc * MAX_BAR_SIZE / 100))
  
  if [[ ${STEP} -ne ${MAX_STEPS} ]] ; then
    echo ""
  fi

  size=${BAR_SIZE//#/ }
  echo -ne "Install (${STEP}/${MAX_STEPS}) [${size}] $perc %${CLEAR_LINE}"
  echo -ne "\rInstall (${STEP}/${MAX_STEPS}) [${BAR_SIZE:0:percBar}\n"

  if [[ ${STEP} -ne ${MAX_STEPS} ]]
  then
    echo -ne "\033[2A"
  fi
}
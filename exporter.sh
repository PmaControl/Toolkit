#!/bin/bash


set -euo pipefail

function get_query()
{
    query=$1
    echo $(mysql -B -N -e "$query")
}

# Extraction d'une table complète en fonction de TABLE_SCHEMA et TABLE_NAME

function get_table()
{
    TABLE_SCHEMA=$1
    TABLE_NAME=$2

    sql="SELECT GROUP_CONCAT(
    CONCAT('\"', COLUMN_NAME, '\", ',  COLUMN_NAME )
    ORDER BY ORDINAL_POSITION ASC
    SEPARATOR ', '
) INTO @json_objects
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '$TABLE_SCHEMA'
 AND TABLE_NAME = '$TABLE_NAME';
SET @sql := CONCAT('SELECT JSON_PRETTY(JSON_ARRAYAGG(JSON_OBJECT(', @json_objects, '))) AS json_data FROM $TABLE_SCHEMA.$TABLE_NAME;');
PREPARE stmt FROM @sql;

EXECUTE stmt;
DEALLOCATE PREPARE stmt;"

    get_query "$sql"
}


version="SELECT SUBSTRING_INDEX(VERSION(), '-', 1) AS 'version', 
CASE  WHEN VERSION() LIKE '%MariaDB%' THEN 'mariadb' 
WHEN SUBSTRING_INDEX(VERSION(), '-', 1) REGEXP '5\\.' THEN 'mariadb' 
ELSE 'mysql'
END AS 'database_name'
FROM DUAL;"

VERSION_BRUT=$(get_query "$version")

VERSION=$(echo $VERSION_BRUT | awk '{print $1}')
TYPE=$(echo $VERSION_BRUT | awk '{print $2}')

echo "/* type : $TYPE - version : $VERSION */" 

if [[ $TYPE == "mariadb" ]]; then

    status="SELECT JSON_OBJECTAGG(VARIABLE_NAME, VARIABLE_VALUE) AS json_data FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME !='FT_BOOLEAN_SYNTAX';"
    # " WHERE VARIABLE_NAME!='FT_BOOLEAN_SYNTAX'"
    variable="SELECT JSON_OBJECTAGG(VARIABLE_NAME, VARIABLE_VALUE) AS json_data FROM information_schema.GLOBAL_VARIABLES;"
else
    status="SELECT JSON_OBJECTAGG(VARIABLE_NAME, VARIABLE_VALUE) AS json_data FROM performance_schema.global_status;"
    variable="SELECT JSON_OBJECTAGG(VARIABLE_NAME, VARIABLE_VALUE) AS json_data FROM performance_schema.global_variables;"
fi

GLOBAL_STATUS=$(get_query "$status")
GLOBAL_VARIABLES=$(get_query "$variable")


USERS=$(get_table "sys" "sys_config")

#echo -e $USERS

RESULT="{\"GLOBAL_STATUS\": [$GLOBAL_STATUS], \"GLOBAL_VARIABLES\": [$GLOBAL_VARIABLES], \"USERS\":[$USERS]}"

echo -e "$RESULT"


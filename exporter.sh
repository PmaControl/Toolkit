#!/bin/bash


result=$(mysql -B -N -e "SELECT VARIABLE_NAME, VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS;" --skip-column-names --raw)

# Créez un tableau JSON
json="{"
while read -r key value; do
    json="$json \"$key\": \"$value\","
done <<< "$result"
json="${json%,}" # Supprimer la virgule finale
GLOBAL_STATUS="$json }"
# Affichez le résultat JSON
echo $GLOBAL_STATUS


#result=$(mysql -B -N -e "SELECT VARIABLE_NAME, VARIABLE_VALUE FROM information_schema.GLOBAL_VARIABLES;" --skip-column-names --raw)

# Créez un tableau JSON
#json="{"
#while read -r key value; do
#    value=$(echo "$value" | sed 's/"/\"/g')
#    value="${value//\"/\\\"}"
#    value=$(printf "%q" "$value")
#    json="$json \"$key\": \"$value\","
#done <<< "$result"
#json="${json%,}" # Supprimer la virgule finale
#GLOBAL_VARIABLES="$json }"
# Affichez le résultat JSON
#echo $GLOBAL_VARIABLES

#RESULT="{\"GLOBAL_STATUS\": $GLOBAL_STATUS, \"GLOBAL_VARIABLES\": $GLOBAL_VARIABLES}"


#echo $RESULT

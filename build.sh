#!/bin/bash
set -e
source lib/6t-include.sh

script=$1


OUTPUT=$(mktemp)


if [[ -f "${OUTPUT}" ]]; then
    rm "${OUTPUT}"
fi

touch ${OUTPUT}

script=$(sed 's:source lib/6t-include.sh::g' $script)

while IFS= read -r line; do
    if [[ "$line" =~ ^include[[:space:]]([a-z0-9/-]+*)$ ]]; then 
        #echo "--->${BASH_REMATCH[1]}"

        file="${BASH_REMATCH[1]}.sh"
        if [[ -f "$file" ]]; then

            TOTAL=$(cat ${BASH_REMATCH[1]}.sh | grep -v '#!/bin/bash')
            #TOTAL=$(./build.sh ${BASH_REMATCH[1]}.sh)
            echo -n "$TOTAL" >> ${OUTPUT}
        else
            echo ""
            echo "Unknow file : $file"
            exit 4
        fi
    else
        echo $line >> ${OUTPUT}
    fi
done <<< "$script"

echo ${OUTPUT}
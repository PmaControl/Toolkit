#!/bin/bash

echo "Sniffing MySQL packets (ASCII mode)..."

tcpdump -nn -i any -s 65535 -l -A "tcp dst port 3306" 2>/dev/null | \
while IFS= read -r line; do
    # Remove binary / control chars
    clean=$(echo "$line" | tr -cd '\11\12\15\40-\176')

    # Match SQL keywords
    if echo "$clean" | grep -Ei 'SELECT|UPDATE|INSERT|DELETE|CREATE|DROP|ALTER|REPLACE|SHOW' >/dev/null; then

        # Remove tcpdump's useless headers
        sql=$(echo "$clean" \
             | sed 's/^.*SELECT/SELECT/i' \
             | sed 's/^.*UPDATE/UPDATE/i' \
             | sed 's/^.*INSERT/INSERT/i' \
             | sed 's/^.*DELETE/DELETE/i' \
             | sed 's/^.*CREATE/CREATE/i' \
             | sed 's/^.*DROP/DROP/i' \
             | sed 's/^.*ALTER/ALTER/i' \
             | sed 's/^.*SHOW/SHOW/i')

        # Skip chunks that aren't real SQL
        if [ ${#sql} -gt 5 ]; then
            echo "[SQL] $sql"
        fi
    fi
done

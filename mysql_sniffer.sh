#!/bin/bash

# Sniffer MySQL en BASH, full portable
# nécessite : tcpdump

echo "Sniffing MySQL traffic on port 3306 (BASH + tcpdump)..."

tcpdump -nn -i any -s 65535 -l -A "tcp dst port 3306" 2>/dev/null | \
while read -r line; do
    # On cherche les lignes contenant un paquet MySQL COM_QUERY
    # Format MySQL (TCP payload):
    #   3 bytes = length
    #   1 byte  = seq id
    #   1 byte  = command (0x03 = COM_QUERY)
    #
    # tcpdump -A affiche en ASCII tout le payload, donc on peut repérer "SELECT", "UPDATE", "INSERT", etc.

    if echo "$line" | grep -E "SELECT|UPDATE|INSERT|DELETE|SHOW|ALTER|CREATE|DROP|REPLACE" >/dev/null; then

        # Récupère l’IP source
        src=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

        # Nettoyage du texte
        sql=$(echo "$line" | sed 's/[^[:print:]]//g' | sed 's/^[ ]*//')

        echo "[$src] $sql"
    fi
done

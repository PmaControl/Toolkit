#!/bin/bash

echo "Sniffing MySQL (clean SQL output)..."

tcpdump -nn -i any -s 65535 -l -xx "tcp dst port 3306" 2>/dev/null | \
awk '
BEGIN {
    sql="";
}

/^[0-9a-f]/ {

    # Remove leading offset (e.g. "0x0010:")
    line=$0;
    sub(/^[0-9a-f]+:/,"",line);

    # Keep only hex bytes
    n=split(line, arr, " ");

    # Parse hex -> chars
    for(i=1;i<=n;i++){
        byte=arr[i];

        if (length(byte)==2 && byte ~ /^[0-9a-fA-F]{2}$/) {
            val = strtonum("0x" byte);

            # MySQL COM_QUERY = hex 03
            if (val == 3 && sql=="") {
                capturing=1;
                next;
            }

            if (capturing==1) {
                # Accept printable characters only
                if (val >= 32 && val <= 126) {
                    sql = sql sprintf("%c", val);
                }
            }
        }
    }
}

/^$/ {
    if (sql != "") {
        print "[SQL] " sql;
        sql="";
        capturing=0;
    }
}
'

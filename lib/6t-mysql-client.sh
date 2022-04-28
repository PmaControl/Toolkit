#!/bin/bash

# Module: lib/6t-mysql-client

# Author: Aurélien LEQUOY
# Email:  aurelien@68koncept.com

#pipe to connect simpply in mysql
function 6t-mysql-query()
{
	rm $error_mysql

    if [ -z "$1" ]
    then
		echo "[mysql][ERROR] server is empty"
		exit 1;
    fi

    if [ -z "$2" ]
    then
		echo "[mysql][ERROR] command is empty"
		exit 2;
    fi

    echo "[mysql] $1 > $2"
	mysql -t -h "$1" -u ${mysql_user} -p${mysql_password} -e "$2" > ${tmp_file} 2> $error_mysql
	error=$(cat $error_mysql)

	if [ "${error}" != "" ]
	then
		echo "[mysql][ERROR] : ${error}"
		exit 13;
	fi

	res=$(cat $tmp_file)
}



function 6t-mysql-parse()
{
	IFS=$'\n\t'

	if [[ $# -eq 0 ]]
	then
		debug "taking file '${tmp_file}' by default"
		#echo "No argument supplied"
	else
		cat $1 > ${tmp_file}
	fi
	
	#mysql -t -B -e "select id,name,class,method from pmacontrol.daemon_main;" > gg
	sed -i '/+-/d' ${tmp_file}
	sed -i -E 's/^\|//g' ${tmp_file}
	sed -i -E 's/\|$//g' ${tmp_file}

	cat ${tmp_file} |head -n1 > head
	sed -i 's/|//g' head
	sed -i -E 's/[[:space:]]+/\t/g' head
	header=$(cat head)

	colones=($header)
	#parse des colones
	k=1

	IFS=$'\t\n';
	debug "###############################################"
	debug "#             get variables                   #"
	debug "###############################################"

	for colone_name in ${colones[*]} 
	do 
		
		#put variable in upper_case
		var=$(echo $colone_name | tr '[:lower:]' '[:upper:]')
		#echo "colone n°$k : $var"
		
		array=($(cut -f$k -d'|' ${tmp_file}))

		j=0
		for val in ${array[*]}
		do
			#trim of value
			val=$(echo $val | sed 's/^[[:space:]]*//g')
			val=$(echo $val | sed 's/[[:space:]]*$//g')

			#$linsed 's/\|$//g' 
			to_eval="MYSQL_${var}_${j}='$val'"
			debug "$to_eval"
			eval $to_eval
			((j=j+1))
		done
		((k=k+1))
	done
	debug "###############################################"
}
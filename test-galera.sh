

dockers=$(docker ps -a --filter "name=node" --format '{{.ID}}')

# Boucle pour supprimer chaque réseau s'il existe
for docker in $dockers; do
    docker inspect "$docker" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Suppression du conteneur $docker ..."
        docker rm -f "$docker"
    fi
done

prefix='galera'
networks=$(docker network ls --filter "name=${prefix}" --format '{{.ID}}')

# Boucle pour supprimer chaque réseau s'il existe
for network in $networks; do
    docker network inspect "$network" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Suppression du réseau $network..."
        docker network rm "$network"
    fi
done

echo "Remove all unused networks. Unused networks are those which are not referenced by any containers."
docker network prune -f



rm -rvf /srv/galera/node1/*
rm -rvf /srv/galera/node2/*
rm -rvf /srv/galera/node3/*

docker network create --subnet 172.18.0.0/24 galera

docker run -d --restart=unless-stopped --net galera \
	--name node1 -h node1 --ip 172.18.0.101 \
	-p 3311:3306 \
	-v /srv/galera/node1.cnf:/etc/mysql/conf.d/galera.cnf \
	-v /srv/galera/node1:/var/lib/mysql \
	-e MYSQL_ROOT_PASSWORD=secret_galera_password \
	-e GALERA_NEW_CLUSTER=1 \
	mariadb:10.6  \
	--wsrep-new-cluster \
	--binlog_format=ROW \
	--default_storage_engine=InnoDB \
	--innodb_autoinc_lock_mode=2 \
	--innodb_flush_log_at_trx_commit=2 \
	--innodb_doublewrite=1 \
	--wsrep_on=ON \
	--wsrep_provider=/usr/lib/libgalera_smm.so \
	--wsrep_sst_method=rsync



docker run -d --restart=unless-stopped --net galera \
	--name node2 -h node2 --ip 172.18.0.102 \
	-p 3312:3306 \
	-v /srv/galera/node2.cnf:/etc/mysql/conf.d/galera.cnf \
	-v /srv/galera/node2:/var/lib/mysql \
	-e MYSQL_ROOT_PASSWORD=secret_galera_password \
	mariadb:10.6 \
	--binlog_format=ROW \
	--default_storage_engine=InnoDB \
	--innodb_autoinc_lock_mode=2 \
	--innodb_flush_log_at_trx_commit=2 \
	--innodb_doublewrite=1 \
	--wsrep_on=ON \
	--wsrep_provider=/usr/lib/libgalera_smm.so \
	--wsrep_sst_method=rsync

docker run -d --restart=unless-stopped --net galera \
	--name node3 -h node3 --ip 172.18.0.103 \
	-p 3313:3306 \
	-v /srv/galera/node3.cnf:/etc/mysql/conf.d/galera.cnf \
	-v /srv/galera/node3:/var/lib/mysql \
	-e MYSQL_ROOT_PASSWORD=secret_galera_password \
	mariadb:10.6 \
	--binlog_format=ROW \
	--default_storage_engine=InnoDB \
	--innodb_autoinc_lock_mode=2 \
	--innodb_flush_log_at_trx_commit=2 \
	--innodb_doublewrite=1 \
	--wsrep_on=ON \
	--wsrep_provider=/usr/lib/libgalera_smm.so \
	--wsrep_sst_method=rsync


sleep 5
mysql -h 127.0.0.1 -P 3311 -u root -psecret_galera_password -e 'SHOW GLOBAL STATUS like "wsrep_cluster_size%"'
mysql -h 127.0.0.1 -P 3312 -u root -psecret_galera_password -e 'SHOW GLOBAL STATUS like "wsrep_cluster_size%"'
mysql -h 127.0.0.1 -P 3313 -u root -psecret_galera_password -e 'SHOW GLOBAL STATUS like "wsrep_cluster_size%"'
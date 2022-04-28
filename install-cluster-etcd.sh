#!/bin/bash

source lib/6t-debug.sh
source lib/6t-ssh.sh
source lib/6t-utils.sh
source lib/6t-apt.sh


# IFS=$'\n\t '

TOKEN="token-01"
CLUSTER=""
CLUSTER_STATE="new"

#load env
#export $(grep -v '^#' .env | xargs)
set -euo pipefail

while getopts 'ht:c:e:v' flag; do
  case "${flag}" in
    h) 
        echo "auto install etcd cluster"
        echo "example : ./etcd.sh -c '127.0.0.1,127.0.0.2,127.0.0.3'"
        echo " "
        echo "options:"
        echo "-h                      display this help"
        echo "-t                      the name of the token"
        echo "-c          	          list of hostname of the cluster, coma separated"
        echo "-e                      state of the cluster"
        echo "-v                      version of this tool"
 
	exit 0
    ;;
    v) TOKEN="${OPTARG}" ;;
    c) CLUSTER="${OPTARG}";;
    g) CLUSTER_SATE="${OPTARG}";;
    v) 
	    
	    exit 0
	    ;;
    *) echo "Unexpected option ${flag}" 
	exit 0
    ;;
  esac
done

############
ssh_private_key=/root/.ssh/id_rsa
ssh_user=root
DEBUG=false
tmp_file=/tmp/gg
error_ssh=/tmp/error

echo "CLUSTER ${CLUSTER}"

ips=$(echo $CLUSTER | tr "," "\n")


#test ssh
for ip in $ips
do
    echo "> [$ip]"
    6t_test_ssh $ip
done



ETCD_VER=v3.4.10

DOWNLOAD_URL=https://storage.googleapis.com/etcd

rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test

curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1

rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

chmod +x /tmp/etcd-download-test/etcd
chmod +x /tmp/etcd-download-test/etcdctl 

#Verify the downloads
/tmp/etcd-download-test/etcd --version
/tmp/etcd-download-test/etcdctl version

#Move them to the bin folder
mv /tmp/etcd-download-test/etcd /usr/local/bin
mv /tmp/etcd-download-test/etcdctl /usr/local/bin


#test ssh
for ip in $ips
do
    echo "> [$ip]"
    scp /usr/local/bin/etcd root@${ip}:/usr/bin/etcd
    scp /usr/local/bin/etcdctl root@${ip}:/usr/bin/etcdctl

    scp /usr/local/bin/etcd root@${ip}:/usr/local/bin/etcd
    scp /usr/local/bin/etcdctl root@${ip}:/usr/local/bin/etcdctl
done


6t-apt golang-cfssl



rm -rvf /root/certs
mkdir /root/certs && cd /root/certs

echo '{"CN":"CA","key":{"algo":"rsa","size":2048}}' | cfssl gencert -initca - | cfssljson -bare ca -

#create ca-key.pem, ca.pem, and ca.csr
echo '{"signing":{"default":{"expiry":"43800h","usages":["signing","key encipherment","server auth","client auth"]}}}' > ca-config.json
  


declare -a hostname
declare -a adress_ip
declare -a cluster_string


cluster_string+="";

i=1
for ip in $ips
do
    6t_ssh $ip hostname
    res="$(echo -e "${res}" | tr -d '[:space:]')"

    hostname[$i]=$res
    adress_ip[$i]=$ip

    #echo "-- $res"

    string1="=https://"
    string2=":2380"

    concat="${res}${string1}${ip}${string2}"
    cluster_string+=($concat)

    i=$i+1
done


CLUSTER_STRING=$(6t-join-by , ${cluster_string[@]})

echo $CLUSTER_STRING


#generate CRT and key for all nodes
for ip in $ips
do
  6t_ssh $ip hostname
  res="$(echo -e "${res}" | tr -d '[:space:]')"

  export NAME=$res
  export ADDRESS=$ip
  echo '{"CN":"'$NAME'","hosts":[""],"key":{"algo":"rsa","size":2048}}' | cfssl gencert -config=ca-config.json -ca=ca.pem -ca-key=ca-key.pem -hostname="$ADDRESS" - | cfssljson -bare $NAME

  USER="root"
  scp ca.pem $USER@$ADDRESS:/etc/etcd/etcd-ca.crt
  scp ${NAME}.pem $USER@$ADDRESS:/etc/etcd/server.crt
  scp ${NAME}-key.pem $USER@$ADDRESS:/etc/etcd/server.key
done

cat > /root/etcd.service << EOF

[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target
 
[Service]
Type=notify
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/bin/etcd
Restart=always
RestartSec=10s
LimitNOFILE=40000
 
[Install]
WantedBy=multi-user.target

EOF

for ip in $ips
do
  6t_ssh $ip "mkdir -p /etc/etcd"

  6t_ssh $ip "install -d -o etcd -g etcd /var/lib/etcd"
  #6t_ssh $ip "chown "

  6t_ssh $ip hostname
  hostname="$(echo -e "${res}" | tr -d '[:space:]')"

  USER="root"
  cat > /root/etcd.conf << EOF

ETCD_NAME="${hostname}"
ETCD_LISTEN_PEER_URLS="https://${ip}:2380"
ETCD_LISTEN_CLIENT_URLS="https://${ip}:2379"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER="${CLUSTER_STRING}"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${ip}:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://${ip}:2379"
ETCD_TRUSTED_CA_FILE="/etc/etcd/etcd-ca.crt"
ETCD_CERT_FILE="/etc/etcd/server.crt"
ETCD_KEY_FILE="/etc/etcd/server.key"
ETCD_PEER_CLIENT_CERT_AUTH=true
ETCD_PEER_TRUSTED_CA_FILE="/etc/etcd/etcd-ca.crt"
ETCD_PEER_KEY_FILE="/etc/etcd/server.key"
ETCD_PEER_CERT_FILE="/etc/etcd/server.crt"
ETCD_DATA_DIR="/var/lib/etcd"

EOF

  scp /root/etcd.conf $USER@${ip}:/etc/etcd/etcd.conf
  scp /root/etcd.service $USER@${ip}:/usr/lib/systemd/system/etcd.service

  6t_ssh $ip "systemctl stop etcd"
  echo $res
  6t_ssh $ip "systemctl daemon-reload"
    echo $res
  6t_ssh $ip "systemctl enable etcd"
    echo $res

done

for ip in $ips
do
    6t_ssh $ip "systemctl start etcd &"
    echo $res
done

sleep 5

for ip in $ips
do
  6t_ssh $ip "systemctl status etcd"
    echo $res
  6t_ssh $ip "etcdctl --endpoints https://${ip}:2379 --cert /etc/etcd/server.crt --cacert /etc/etcd/etcd-ca.crt --key /etc/etcd/server.key put foo bar"
    echo $res
  6t_ssh $ip "etcdctl --endpoints https://${ip}:2379 --cert /etc/etcd/server.crt --cacert /etc/etcd/etcd-ca.crt --key /etc/etcd/server.key get foo"
    echo $res

  6t_ssh $ip "curl --cacert /etc/etcd/etcd-ca.crt --cert /etc/etcd/server.crt --key /etc/etcd/server.key https://${ip}:2379/health"
    echo $res
  6t_ssh $ip "etcdctl --endpoints https://${ip}:2379 --cert /etc/etcd/server.crt --cacert /etc/etcd/etcd-ca.crt --key /etc/etcd/server.key member list"
    echo $res
done

echo "########################"

echo $error_ssh
cat $error_ssh
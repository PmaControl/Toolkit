#! /bin/bash

PKG_LIST=(
lsb-release
zip
unzip
bc
pv
wget
gnupg
gnupg2
net-tools
git
tig
)

PKG_LIST_2=(
php7.4
apache2
graphviz
php7.4-mysql
php7.4-ldap
php7.4-json
php7.4-curl
php7.4-cli
php7.4-mbstring
php7.4-intl
php7.4-fpm
libapache2-mod-php7.4
php7.4-gd
php7.4-xml
)

PKG_UPDATE()
{
    if [ $# -ne 0 ]
    then
        echo "USAGE: PKG_UPDATE"
        return 1
    fi
    
    execute "apt-get -y update"
    test_log
}

PKG_UPGRADE()
{
    if [ $# -ne 0 ]
    then
        echo "USAGE: PKG_UPDATE"
        return 1
    fi
    
    execute "apt-get -y upgrade"
    test_log
    
}

PKG_INSTALL()
{
    if [ $# -ne 1 ]
    then
        echo "USAGE: PKG_UPDATE [PACKAGE_NAME]"
        return 1
    fi

    REQUIRED_PKG=$1
    COLORED_PKG="\033[1;95m${REQUIRED_PKG}\033[0m"
    
    if [[ ! -f $PACKAGE_LIST ]]
    then
        display "Request package list installed"
        ALL_PACKAGES_INSTALLED=$(execute "dpkg -l | grep ii | cut -d ' '  -f 3 | cut -d ':' -f 1") 
        cp -a "$GENERAL_LOG" "$PACKAGE_LIST"
    fi

    #echo "cat"
    #cat $PACKAGE_LIST
    
    RES=$(cat "$PACKAGE_LIST" | grep "^$REQUIRED_PKG$")

    if [ "$RES" = "$REQUIRED_PKG" ]
    then
        display "${COLORED_PKG} already installed."
    else
        display "No $COLORED_PKG. Setting up $COLORED_PKG."

        SSH_VAR="DEBIAN_FRONTEND=noninteractive"
        execute "apt --yes install $REQUIRED_PKG"
        test_log
        display "${COLORED_PKG} installed."
    fi
}
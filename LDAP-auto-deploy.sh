#!/bin/bash
# Automate LDAP Lab Server and Clients by Jacob / WowEhm

set -e

SERVER_IP="172.16.30.47"
CLIENT_IP="172.16.31.47"
HAPPY_IP="172.16.32.47"
PEACHY_IP="172.16.33.47"

###############
# SERVER SIDE
###############
echo "=== SERVER SIDE BEGIN ==="

subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms || true

check_install() {
    PKG="$1"
    if rpm -q $PKG >/dev/null 2>&1; then
        echo "[OK] $PKG already installed."
    else
        echo "[INSTALL] Installing $PKG..."
        yum -y install $PKG
    fi
}


# install openldap* 
check_install openldap-servers
check_install openldap-clients
check_install nss-pam-ldapd


mkdir -p /var/lib/ldap/example47.lab
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/example47.lab/DB_CONFIG
chown ldap:ldap /var/lib/ldap/example47.lab/*
chown ldap:ldap /var/lib/ldap/example47.lab
chmod 700 /var/lib/ldap/example47.lab

# Replace slapd.d
cd /etc/openldap
mv slapd.d slapd.d.backup 2>/dev/null || true

# slapd.conf setup
cat > /etc/openldap/slapd.conf <<'EOF'
# GLOBAL CONFIG (for ldap structure)
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
include /etc/openldap/schema/nis.schema

pidfile /var/run/openldap/slapd.pid
loglevel 256

database bdb
suffix "dc=example47,dc=lab"
directory /var/lib/ldap/example47.lab

rootdn "cn=ldapadm,dc=example47,dc=lab"
rootpw secret
EOF

slaptest -u -f /etc/openldap/slapd.conf

systemctl enable --now slapd

###############
# CREATE LDIFS
###############
mkdir -p /etc/openldap/ldifs
cd /etc/openldap/ldifs

# base.ldif
cat > base.ldif <<'EOF'
dn: dc=example47,dc=lab
dc: example47
objectclass: top
objectclass: domain
EOF

# ou.ldif
cat > ou.ldif <<'EOF'
#users OU
dn: ou=accounts,dc=example47,dc=lab
ou: accounts
objectClass: top
objectClass: organizationalUnit

#groups OU
dn: ou=groups,dc=example47,dc=lab
ou: groups
objectClass: top
objectClass: organizationalUnit

#hosts OU
dn: ou=hosts,dc=example47,dc=lab
ou: hosts
objectClass: top
objectClass: organizationalUnit
EOF

# leaf.ldif
cat > leaf.ldif <<'EOF'
# user linuxuser1
dn: uid=linuxuser1,ou=accounts,dc=example47,dc=lab
objectClass: inetorgPerson
objectClass: posixAccount
cn: user 1
sn: user 1
uid: linuxuser1
uidNumber: 1001
gidNumber: 1000
homeDirectory: /home/linuxuser1
loginShell: /bin/bash
mail: linuxuser1@example47.lab
userPassword:

# user linuxuser2
dn: uid=linuxuser2,ou=accounts,dc=example47,dc=lab
objectClass: inetorgPerson
objectClass: posixAccount
cn: user 2
sn: user 2
uid: linuxuser2
uidNumber: 1002
gidNumber: 1000
homeDirectory: /home/linuxuser2
loginShell: /bin/bash
mail: linuxuser2@example47.lab
userPassword:

# user linuxuser3
dn: uid=linuxuser3,ou=accounts,dc=example47,dc=lab
objectClass: inetorgPerson
objectClass: posixAccount
cn: user 3
sn: user 3
uid: linuxuser3
uidNumber: 1003
gidNumber: 1000
homeDirectory: /home/linuxuser3
loginShell: /bin/bash
mail: linuxuser3@example47.lab
userPassword:

#group users
dn: cn=users,ou=groups,dc=example47,dc=lab
objectclass: posixGroup
cn: user
gidNumber: 1000
memberUid: linuxuser1
memberUid: linuxuser2
memberUid: linuxuser3
EOF

# hostsleaf.ldif
cat > hostsleaf.ldif <<EOF
dn: cn=happy.example47.lab,ou=hosts,dc=example47,dc=lab
objectClass: device
objectClass: ipHost
cn: happy.example47.lab
ipHostNumber: ${HAPPY_IP}

dn: cn=peachy.example47.lab,ou=hosts,dc=example47,dc=lab
objectClass: device
objectClass: ipHost
cn: peachy.example47.lab
ipHostNumber: ${PEACHY_IP}
EOF

# email.ldif
cat > email.ldif <<'EOF'
dn: uid=linuxuser1,ou=accounts,dc=example47,dc=lab
changetype: modify
add: mail
mail: linuxuser1-alt@example47.lab
EOF

# Add entries
ldapadd -x -D "cn=ldapadm,dc=example47,dc=lab" -w secret -f base.ldif || true
ldapadd -x -D "cn=ldapadm,dc=example47,dc=lab" -w secret -f ou.ldif || true
ldapadd -x -D "cn=ldapadm,dc=example47,dc=lab" -w secret -f leaf.ldif || true
ldapadd -x -D "cn=ldapadm,dc=example47,dc=lab" -w secret -f hostsleaf.ldif || true
ldapmodify -x -D "cn=ldapadm,dc=example47,dc=lab" -w secret -f email.ldif || true

#####################
# SERVER CONFIG FILES
#####################

# /etc/openldap/ldap.conf
cat > /etc/openldap/ldap.conf <<'EOF'
BASE    dc=example47,dc=lab
URI ldap://127.0.0.1 ldap://172.16.30.47
EOF

# Install nss-pan-ldapd
check_install nss-pam-ldapd
#yum install -y nss-pam-ldapd || true

# /etc/nslcd.conf
cat > /etc/nslcd.conf <<'EOF'
uid nslcd
gid ldap
uri ldap://127.0.0.1/
base dc=example47,dc=lab
TLS_CACERTDIR /etc/openldap/certs
EOF

# Add ldap to nsswitch
sed -i 's/^hosts:.*/hosts:      files dns myhostname ldap/' /etc/nsswitch.conf

systemctl restart nslcd

###########
# IPTABLES
###########

iptables -F
iptables -A INPUT -p tcp --dport 389 -s 172.16.31.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 389 -s 172.16.32.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 389 -s 172.16.30.0/24 -j REJECT

echo "=== SERVER READY ==="

#################
# CLIENT SIDE SSH
#################
echo "=== SSHING TO CLIENT (172.16.31.47) ==="

ssh root@172.16.31.47 bash <<'EOF'
set -e

check_install() {
    PKG="$1"
    if rpm -q $PKG >/dev/null 2>&1; then
        echo "[OK] $PKG already installed."
    else
        echo "[INSTALL] Installing $PKG..."
        yum -y install $PKG
    fi
}


check_install openldap-clients
check_install nss-pam-ldapd


# Client nslcd.conf
cat > /etc/nslcd.conf <<'EOF2'
uri ldap://172.16.30.47/
base dc=example47,dc=lab
TLS_CACERTDIR /etc/openldap/certs
EOF2

# Client ldap.conf
cat > /etc/openldap/ldap.conf <<'EOF3'
BASE    dc=example47,dc=lab
URI ldap://127.0.0.1 ldap://172.16.30.47
EOF3

# Client nsswitch configuration
cat > /etc/nsswitch.conf <<'EOF4'
passwd:     files sss systemd ldap
group:      files sss systemd ldap
shadow:     files sss ldap
hosts:      files dns myhostname ldap
EOF4

systemctl restart nslcd

echo "[CLIENT] ldapsearch test:"
ldapsearch -x -H ldap://172.16.30.47 -b dc=example47,dc=lab

echo "[CLIENT] getent hosts:"
getent hosts
EOF

echo "=== DONE ==="

#check iptables ldap ports for proper accept/reject
iptables -L INPUT -n --line-numbers


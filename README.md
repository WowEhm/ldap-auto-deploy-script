# LDAP Auto Deploy Script

Created by Jacob Carter / WowEhm

A fully automated OpenLDAP + client configuration script designed for lab environments (CentOS/RHEL).  
This script installs, configures, and validates:

- OpenLDAP server
- Base DIT structure
- RootDN + rootPW
- ACLs
- Iptables/Firewall rules
- NSS LDAP client integration
- Testing commands (ldapadd, ldapsearch, getent)

## Requirements
- RHEL/CentOS 7/8
- root privileges
- Internet access or local repos
- Server + client IPs set correctly in the script
- Proper SSH keys with Client

## Using Bash

sudo bash LDAP-auto-deploy.sh

## For successful Demo run 
slaptest -u
ldapsearch -x -H ldap://server-ip -b dc=example,dc=lab
getent hosts

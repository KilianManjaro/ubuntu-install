#!/usr/bin/env bash
# Install script for Unix Server
# Version: Ubuntu_16.04_LTS
# Maintainer: Tim Harris <tim@timharris.org>
#
# This will configure an Ubuntu server host to a Rho standard specification.
# Specifically, one the hostname is finalized, it configures:
#  - postfix
#  - filebeat
#  - ossec-hids for Alienvault

#Set your desired package version numbers
AV="ossec-hids-2.9.0.tar.gz"
MAILRELAY="mx-out-rr.xxx.xxx.com" # $MAILRELAY was not defined previously...

### SECTION: PREPARATION
WERK=${PWD}
mkdir -p /tmp/software
SOFTWARE=/tmp/software
cd $SOFTWARE

#Now we set some variables
OSSEC_PORT="1515"
CLIENT=$(hostname -s).$(hostname -d)
LOCALIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
OCTET=$(echo $LOCALIP | cut -d . -f 2)
if [ $OCTET = 2 ]
then HOMEVAULT="xxx.x.xx.xxx"
elif [ $OCTET = 3 ]
then HOMEVAULT="xxx.x.xx.xxx"
fi

### SECTION: POSTFIX_SMTP

# Install
debconf-set-selections <<< "postfix postfix/mailname string $CLIENT"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet with smarthost'"
apt-get install mailutils python-mailutils mailutils-dbg -y

sed -ri "s@inet_interfaces = all@inet_interfaces = localhost@" /etc/postfix/main.cf
sed -ri "s@smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem@smtpd_tls_cert_file=/etc/ssl/certs/$CLIENT.pem@" /etc/postfix/main.cf
sed -ri "s@smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key@smtpd_tls_key_file=/etc/ssl/private/$CLIENT.key@" /etc/postfix/main.cf
sed -ri "s@inet_protocols = all@inet_protocols = ipv4@" /etc/postfix/main.cf
sed -ri "s@relayhost =@relayhost = $MAILRELAY@" /etc/postfix/main.cf
echo "xxx.com" > /etc/mailname
echo "masquerade_domains = .xxx.com xxx.com" >> /etc/postfix/main.cf
echo "smtp_generic_maps = hash:/etc/postfix/generic" >> /etc/postfix/main.cf
touch /etc/postfix/generic
echo "root@xxx.com admin@xxx.com" >> /etc/postfix/generic
postmap /etc/postfix/generic
service postfix restart

# echo "This is just a test." | mail -s "Test from `hostname -A`" mnorland@rhoworld.com

### SECTION: /POSTFIX_SMTP

### SECTION: Remote_Logs

# Install our Filebeat log sender
echo "Installing our filebeat log sender..."
wget --no-check-certificate https://aptitude.xxx.xxx.com/software/elastic/filebeat-6.2.2-amd64.deb
dpkg -i $SOFTWARE/filebeat-*-amd64.deb
systemctl start filebeat
systemctl enable filebeat.service

echo ""
echo "configuring filebeat for our logstash pipeline instance..."
LOS=$(getent hosts logs.$(hostname -d) | head -n 1 | cut -d' ' -f1)
# handle a DNS failure gracefully, so the filebeat.yml is easy to change/correct after if needed
if [ -z $LOS ]; then LOS="LOCALHOST"; fi
sed -ri "s@localhost@"$LOS"@" /etc/filebeat/filebeat.yml
sed -ri "s@#hosts:@hosts:@" /etc/filebeat/filebeat.yml
sed -ri "s@#output.logstash:@output.logstash:@" /etc/filebeat/filebeat.yml
sed -ri "s@output.elasticsearch:@#output.elasticsearch:@" /etc/filebeat/filebeat.yml
sed -ri 's@"/etc/pki/root/ca.pem"@"/etc/ssl/certs/DigicertCA.crt"@' /etc/filebeat/filebeat.yml
sed -ri 's@#ssl.certificate_authorities:@ssl.certificate_authorities:@' /etc/filebeat/filebeat.yml
sed -ri "s@#ssl.certificate:@ssl.certificate:@" /etc/filebeat/filebeat.yml
sed -ri "s@/etc/pki/client/cert.pem@/etc/ssl/certs/$(hostname).$(dnsdomainname).crt@" /etc/filebeat/filebeat.yml
sed -ri "s@#ssl.key:@ssl.key:@" /etc/filebeat/filebeat.yml
sed -ri "s@/etc/pki/client/cert.key@/etc/ssl/private/$(hostname).$(dnsdomainname).key@" /etc/filebeat/filebeat.yml
sed -ri "s@#logging.level: debug@logging.level: debug@" /etc/filebeat/filebeat.yml
/usr/bin/filebeat.sh -configtest -e
systemctl restart filebeat

### SECTION: /Remote_Logs


### SECTION: OSSEC

# Get our ossec-HIDS
wget --no-check-certificate https://aptitude.xxx.xxx.com/software/ossec/$AV
OSSEC_SOURCE=$(find $SOFTWARE/ossec-hids-*)
echo "Installing our ossec package"
echo ""
cd /opt
tar zxf $OSSEC_SOURCE
rm -rf $OSSEC_SOURCE
HIDS=$(find ossec-hids-* -maxdepth 0)
cat <<EOT > /opt/$HIDS/etc/preloaded-vars.conf
# preloaded-vars.conf, Daniel B. Cid (dcid @ ossec.net).
#
# Use this file to customize your installations.
# It will make the install.sh script pre-load some
# specific options to make it run automatically
# or with less questions.

# PLEASE NOTE:
# When we use "n" or "y" in here, it should be changed
# to "n" or "y" in the language your are doing the
# installation. For example, in portuguese it would
# be "s" or "n".


# USER_LANGUAGE defines to language to be used.
# It can be "en", "br", "tr", "it", "de" or "pl".
# In case of an invalid language, it will default
# to English "en"
USER_LANGUAGE="en"     # For english
#USER_LANGUAGE="br"     # For portuguese


# If USER_NO_STOP is set to anything, the confirmation
# messages are not going to be asked.
USER_NO_STOP="y"


# USER_INSTALL_TYPE defines the installation type to
# be used during install. It can only be "local",
# "agent" or "server".
#USER_INSTALL_TYPE="local"
USER_INSTALL_TYPE="agent"
#USER_INSTALL_TYPE="server"


# USER_DIR defines the location to install ossec
USER_DIR="/var/ossec"


# If USER_DELETE_DIR is set to "y", the directory
# to install OSSEC will be removed if present.
#USER_DELETE_DIR="y"


# If USER_ENABLE_ACTIVE_RESPONSE is set to "n",
# active response will be disabled.
USER_ENABLE_ACTIVE_RESPONSE="y"


# If USER_ENABLE_SYSCHECK is set to "y",
# syscheck will be enabled. Set to "n" to
# disable it.
USER_ENABLE_SYSCHECK="y"


# If USER_ENABLE_ROOTCHECK is set to "y",
# rootcheck will be enabled. Set to "n" to
# disable it.
USER_ENABLE_ROOTCHECK="y"


# If USER_UPDATE is set to anything, the update
# installation will be done.
#USER_UPDATE="y"

# If USER_UPDATE_RULES is set to anything, the
# rules will also be updated.
#USER_UPDATE_RULES="y"

# If USER_BINARYINSTALL is set, the installation
# is not going to compile the code, but use the
# binaries from ./bin/
#USER_BINARYINSTALL="x"


### Agent Installation variables. ###

# Specifies the IP address or hostname of the
# ossec server. Only used on agent installations.
# Choose only one, not both.
USER_AGENT_SERVER_IP="WHICH_SERVER"
# USER_AGENT_SERVER_NAME


# USER_AGENT_CONFIG_PROFILE specifies the agent's config profile
# name. This is used to create agent.conf configuration profiles
# for this particular profile name. Only used on agent installations.
# Can be any string. E.g. LinuxDBServer or WindowsDomainController
USER_AGENT_CONFIG_PROFILE="generic"



### Server/Local Installation variables. ###

# USER_ENABLE_EMAIL enables or disables email alerting.
#USER_ENABLE_EMAIL="y"

# USER_EMAIL_ADDRESS defines the destination e-mail of the alerts.
#USER_EMAIL_ADDRESS="dcid@test.ossec.net"

# USER_EMAIL_SMTP defines the SMTP server to send the e-mails.
#USER_EMAIL_SMTP="test.ossec.net"


# USER_ENABLE_SYSLOG enables or disables remote syslog.
#USER_ENABLE_SYSLOG="y"


# USER_ENABLE_FIREWALL_RESPONSE enables or disables
# the firewall response.
#USER_ENABLE_FIREWALL_RESPONSE="y"


# Enable PF firewall (OpenBSD, FreeBSD and Darwin only)
#USER_ENABLE_PF="y"


# PF table to use (OpenBSD, FreeBSD and Darwin only).
#USER_PF_TABLE="ossec_fwtable"


# USER_WHITE_LIST is a list of IPs or networks
# that are going to be set to never be blocked.
#USER_WHITE_LIST="192.168.2.1 192.168.1.0/24"


#### exit ? ###
EOT
sed -ri "s@WHICH_SERVER@$HOMEVAULT@g" /opt/$HIDS/etc/preloaded-vars.conf
cd ossec-hids-*
./install.sh

# Reach out to server via authd and get our key.
echo "Getting our key from the Alienvault server"
echo ""
/var/ossec/bin/agent-auth -A $CLIENT -m $HOMEVAULT -p $OSSEC_PORT
touch /var/ossec/etc/shared/agent.conf
/etc/init.d/ossec restart

#clean up
cd /opt
rm -rf preloaded-vars.patch
apt-get autoremove -y
apt-get autoclean -y
reboot
exit 0

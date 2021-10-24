#!/usr/bin/env bash
# Install script for Unix Server
# Version: Ubuntu_16.04_LTS
# Maintainer: Tim Harris <tim@timharris.org>
#
# This will configure the base Ubuntu server host to a Rho standard specification.
# In addition it will provide:
#  - ENV specific shell prompts to minimize errors
#  - FISMA banners / warnings
#  - Disable IPv6
#  - configure use of our local apt repository
#  - improved random number generation
#  - NTP


### SECTION: PREPARATION
WERK=${PWD}
mkdir -p /tmp/software
SOFTWARE=/tmp/software
cd $SOFTWARE

#Now we set some variables
APT=$(ps -ef | grep /usr/bin/unattended-upgrade | grep -v grep | awk '{ print $2 }')

#before we start we need to kill any unattended-upgrades
[[ ! -z $APT ]] && kill -9 $APT

# cleanup from the OS installation.
userdel --force --remove installer

### SECTION: /PREPARATION

### SECTION: Prompt_ENV
# add the environment from our FQDN to our prompt, e.g. instead of user@hostname$ we get user@hostname.ENV$

cat <<'EOT' > bashrc.patch
*** /etc/bash.bashrc.orig       2015-08-31 19:27:45.000000000 -0400
--- /etc/bash.bashrc    2017-09-15 00:43:20.762154426 -0400
***************
*** 16,22 ****
  fi

  # set a fancy prompt (non-color, overwrite the one in /etc/profile)
! PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '

  # Commented out, don't overwrite xterm -T "title" -n "icontitle" by default.
  # If this is an xterm set the title to user@host:dir
--- 16,25 ----
  fi

  # set a fancy prompt (non-color, overwrite the one in /etc/profile)
! #PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
! SUBDOMAIN=$(hostname -f | cut -f2 -d. | tr [:lower:] [:upper:])
! PS1='${debian_chroot:+($debian_chroot)}\u@\h.'$SUBDOMAIN':\w\$ '
! alias fix='export PS1="${debian_chroot:+($debian_chroot)}\u@\h.'$SUBDOMAIN':\w\$ "'

  # Commented out, don't overwrite xterm -T "title" -n "icontitle" by default.
  # If this is an xterm set the title to user@host:dir
EOT
patch /etc/bash.bashrc bashrc.patch
rm -rf bashrc.patch
source /etc/bash.bashrc

### SECTION: /Prompt_ENV

### SECTION: FISMA_MOTD

#add ou messaging
cat <<EOT > /etc/issue
This system is restricted to authorized users for authorized use only.
Individuals attempting unauthorized access will be prosecuted to the full
extent of the law under the Computer Fraud and Abuse Act of 1986 or other
applicable laws. Use of this system constitutes notitification and consent
to monitoring and auditing of all system activities and data.
All terms described above are subject to change without any given notice.

If you are not in compliance with the above terms, terminate access now!

EOT

sed -ri "s@#Banner /etc/issue.net@Banner /etc/issue@" /etc/ssh/sshd_config
service sshd restart

### SECTION: /FISMA_MOTD

### SECTION: IPv6_OFF

# Eliminate IPv6
cat <<EOT >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
#
fs.file-max = 800000
#
EOT
sysctl -p

### SECTION: /IPv6_OFF

### SECTION: RHO_APT

wget --no-check-certificate https://aptitude.xxxxx/software/apt-transport-https_1.2.24_amd64.deb
dpkg -i $SOFTWARE/apt-transport-https_*
rm apt-transport-https_*.deb

# Here we do our apt stuff
#turn off apt.daily
systemctl disable apt-daily.service
systemctl disable apt-daily.timer
echo "APT::Periodic::Unattended-Upgrade "0";" >> /etc/apt/apt.conf.d/10periodic

# now we make some files
cat <<EOT > /etc/apt/sources.list
#
# aptitude repository sources, xxx (c) $(date +"%Y")
# Maintainer: Tim Harris <tim@timharris.org>
#

# ubuntu
deb https://xxxxx/xenial-current xenial main restricted universe
deb https://xxxxx/xenial-updates xenial updates-main updates-restricted updates-universe
deb https:/xxxxx/xenial-security xenial security-main security-restricted security-universe
#
EOT

# Add our apt key
cat <<EOT > aptkey.txt
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1

<insert key here>

-----END PGP PUBLIC KEY BLOCK-----
EOT

#roll in our DigiCert CA cert
cat <<EOT > /usr/local/share/ca-certificates/DigiCertCA.crt
-----BEGIN CERTIFICATE-----

-----END CERTIFICATE-----
EOT

update-ca-certificates
apt-key add aptkey.txt
rm -rf aptkey.txt

### SECTION: /RHO_APT

### SECTION: RHO_BASE_APT_PKGS

# basic packages
apt-get update
apt-get install \
 build-essential \
 dkms \
 open-vm-tools \
 expect \
 jq \
 equivs \
 auditd \
 zip \
 haveged \
 libdieharder3 \
 libhavege-dev \
 rng-tools \
 libssl-dev \
 zlib1g \
 gnupg2 \
 gpgv2 \
 subversion \
 ntp \
 ntpdate \
 unzip \
 lsscsi \
 screen \
 -y

# network tools
apt-get install \
 arptables \
 arpwatch \
 ebtables \
 ipset \
 iptraf \
 iptstate \
 netcat-openbsd \
 nmap \
 stunnel4 \
 -y

# performance tools
apt-get install \
 dstat \
 iotop \
 latencytop \
 linux-tools-generic \
 sysstat \
 -y

### ADD A CRON JOB FOR APT SECURITY UPDATES
# Monday evening cronjob, will email admin if a host reports 'reboot' set
cat  <<EOF > /etc/cron.d/apt-security.sh
#!/bin/sh
# update security packages and check for reboot condition

set -e
apt-get update
apt-get upgrade -s | grep -i $(lsb_release -c | awk "{print $2}" | cut -f2)-security | awk '{print $2}' | cut -f1 > /tmp/$(date +%d%m%Y)-security.txt
grep security /etc/apt/sources.list > /tmp/security.list
apt-get upgrade  -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -oDir::Etc::Sourcelist=/tmp/security.list -y
if [ -f "/var/run/reboot-required" ]; then
        echo "$(cat /tmp/*-security.txt)" | mail -s "Reboot required on $(hostname).$(dnsdomainname)" -a "From: admin@xxx.com" user@domain.com
fi
EOF
chmod 0744 /etc/cron.d/apt-security.sh
chmod g+s /var/spool/cron/crontabs
echo "30 22 * * 2 /etc/cron.d/apt-security.sh" >> /var/spool/cron/crontabs/root
#chmod 0744 /var/spool/cron/crontabs/root

#### SUBSECTION: RNG-TOOLS
#modify our rng-tools setup
sed -ri "s@#HRNGDEVICE=/dev/null@HRNGDEVICE=/dev/urandom@" /etc/default/rng-tools
systemctl enable rng-tools.service
systemctl start rng-tools.service
#### SUBSECTION: /RNG-TOOLS

#### SUBSECTION: NTP

/etc/init.d/ntp stop
sed -ri "s/^pool/#pool/gi" /etc/ntp.conf
echo >> /etc/ntp.conf "# --- Rho TIMESERVERS -----
server ntp.xxx.xxx.com
server ntp.xxx.xxx.com"
ntpdate ntp.xxx.xxx.com
systemctl enable ntp
service ntp start

# remove ntpdate due to bug/conflict: https://bugs.launchpad.net/ubuntu/+source/ntp/+bug/1577596
apt-get remove ntpdate -y

#### SUBSECTION: /NTP

### SECTION: /RHO_BASE_APT_PKGS


### SECTION: RHO_BASE_Firewall
ufw allow OpenSSH
ufw --force enable
sed -ri "s@IPV6=yes@IPV6=no@" /etc/default/ufw
sed -ri 's@DEFAULT_FORWARD_POLICY="DROP"@DEFAULT_FORWARD_POLICY="ACCEPT"@' /etc/default/ufw
systemctl enable ufw.service
systemctl restart ufw.service

### SECTION: /RHO_BASE_Firewall

apt-get update
# we do not want apt to prompt for conf files related to 'issue' but we do not want to
# make this setting permanent across the board so we add this here for this turn only.
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y

updatedb

reboot
exit 0

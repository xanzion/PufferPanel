#!/bin/bash
# PufferPanel Installer Script

export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root!" 1>&2
   exit 1
fi

if [ "$SUDO_USER" == "" ]; then
	SUDO_USER="root"
fi

RED="\e[31m"
NORMAL="\e[0m"

if type apt-get &> /dev/null; then
    if [[ -f /etc/debian_version || -f /etc/redhat-release ]]; then
        echo -e "System detected as some variant of Ubuntu/Redhat or Debian."
        OS_INSTALL_CMD="apt-get"
    else
        echo -e "${RED}This OS does not appear to be supported by this program!${NORMAL}"
        exit 1
    fi
elif type yum &> /dev/null; then
    echo -e "System detected as CentOS variant."
    OS_INSTALL_CMD="yum"
else
    echo -e "${RED}This OS does not appear to be supported by this program, or apt-get/yum is not installed!${NORMAL}"
    exit 1
fi

SSL_COUNTRY="US"
SSL_STATE="New-York"
SSL_LOCALITY="New-York"
SSL_ORG="PufferPanel"
SSL_ORG_NAME="SSL"
SSL_EMAIL="auto-generate@ssl.example.com"
SSL_COMMON="{{ node.fqdn }}"
SSL_PASSWORD=""

function checkResponseCode() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}An error occured while installing, halting...${NORMAL}"
        exit 1
    fi
}

# Install NodeJS Dependencies
if [ $OS_INSTALL_CMD == 'apt-get' ]; then
    curl -sL https://deb.nodesource.com/setup_4.x | bash -
else
    curl -sL https://rpm.nodesource.com/setup_4.x | bash -
fi
checkResponseCode

# Install Docker
curl -sSL https://get.docker.com/ | sh
checkResponseCode

# Install Other Dependencies
echo "Installing some dependiencies."
if [ $OS_INSTALL_CMD == 'apt-get' ]; then
    apt-get install -y openssl curl git make gcc g++ nodejs openjdk-7-jdk tar python
else
    yum -y install openssl curl git make gcc-c++ nodejs java-1.8.0-openjdk-devel tar python
fi
checkResponseCode

# Add your user to the docker group
echo "Configuring Docker for:" $SUDO_USER
usermod -aG docker $SUDO_USER
checkResponseCode

# Add the Scales User Group
groupadd --system scalesuser
checkResponseCode

# Change the SFTP System
sed -i '/Subsystem sftp/c\Subsystem sftp internal-sftp' /etc/ssh/sshd_config
checkResponseCode

# Add Match Group to the End of the File
echo -e "Match group scalesuser
    ChrootDirectory %h
    X11Forwarding no
    AllowTcpForwarding no
    ForceCommand internal-sftp" >> /etc/ssh/sshd_config
checkResponseCode

# Restart SSHD
if [ $OS_INSTALL_CMD == 'apt-get' ]; then
    service ssh restart
else
    service sshd restart
fi
checkResponseCode

# Ensure /srv exists
mkdir -p /srv
checkResponseCode

# Clone the repository
git clone https://github.com/PufferPanel/Scales /srv/scales
checkResponseCode

cd /srv/scales
checkResponseCode

# Checkout the Latest Version of Scales
git checkout tags/$(git describe --abbrev=0 --tags)
checkResponseCode

# Install the dependiencies for Scales to run.
npm install
checkResponseCode

# Generate SSL Certificates
openssl req -x509 -days 365 -newkey rsa:4096 -keyout https.key -out https.pem -nodes -passin pass:$SSL_PASSWORD \
    -subj "/C=$SSL_COUNTRY/ST=$SSL_STATE/L=$SSL_LOCALITY/O=$SSL_ORG/OU=$SSL_ORG_NAME/CN=$SSL_COMMON/emailAddress=$SSL_EMAIL"
checkResponseCode

echo '{
	"listen": {
		"sftp": {{ node.daemon_sftp }},
		"rest": {{ node.daemon_listen }},
		"socket": {{ node.daemon_console }},
		"uploads": {{ node.daemon_upload }}
	},
	"urls": {
		"repo": "{{ settings.master_url }}auth/remote/pack",
		"download": "{{ settings.master_url }}auth/remote/download",
		"install": "{{ settings.master_url }}auth/remote/install-progress"
	},
	"ssl": {
		"key": "https.key",
		"cert": "https.pem"
	},
	"basepath": "{{ node.daemon_base_dir }}",
	"keys": [
		"{{ node.daemon_secret }}"
	],
	"upload_maxfilesize": 100000000
}' > config.json
checkResponseCode

npm start
checkResponseCode

echo "Successfully Installed Scales"
exit 0

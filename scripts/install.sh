#!/bin/bash

# update hostname
current_name=`cat /etc/hostname`
read -p "Enter server full hostname ($current_name): " name
sudo sh -c "echo ${name:-$current_name} > /etc/hostname"

# read in other variables
read -p "Enter ssh port (default: 12221): " port
read -p "Enter ssh public key to authorize access: " key
if [ -z "$key" ]
then
	echo "You must enter a public key, otherwise you won't be able to access your server." 
	exit 1
fi
read -p "Enter enter telegram bot token (press enter to skip): " token
if [ -n "$token" ]
then
	read -p "Enter enter telegram user id: " user
	if [ -z "$user" ]
		echo "Telegram alerting will be disabled until a user id is set."
	fi
fi

sudo apt update && sudo apt upgrade
sudo apt dist-upgrade && sudo apt autoremove

sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:ethereum/ethereum
sudo apt update
sudo apt install -y geth git gcc g++ make cmake pkg-config libssl-dev

git clone https://github.com/lightclient/staking $HOME/.config/staking

cd $HOME/.config/staking



# install go-ethereum
sudo useradd --no-create-home --shell /bin/false geth
sudo mkdir -p /var/lib/geth
sudo chown -R geth:geth /var/lib/geth
sudo systemctl link $HOME/.config/staking/services/geth.service
sudo systemctl start geth
sudo systemctl enable geth

# build lighthouse
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

git clone https://github.com/sigp/lighthouse
make --directory lighthouse
sudo cp $HOME/.cargo/bin/lighthouse /usr/local/bin

# setup validator
sudo useradd --no-create-home --shell /bin/false validator
sudo mkdir -p /var/lib/lighthouse
sudo chown -R matt:matt /var/lib/lighthouse

mkdir -p $HOME/keys
sudo chmod 700 $HOME/keys
read -p "Copy validator keys to ~/keys and press any key to continue...\n" -n1 -s

lighthouse --network pyrmont account validator import --directory $HOME/keys --datadir /var/lib/lighthouse
sudo chown root:root /var/lib/lighthouse
sudo systemctl link $HOME/.config/staking/services/validator.service

sudo chown -R root:root /var/lib/lighthouse
sudo chown -R validator:validator /var/lib/lighthouse/validator

# setup beacon
sudo useradd --no-create-home --shell /bin/false beacon
sudo mkdir -p /var/lib/lighthouse/beacon
sudo chown -R beacon:beacon /var/lib/lighthouse/beacon
sudo systemctl link $HOME/.config/staking/services/beacon.service

sudo systemctl start beacon
sudo systemctl start validator
sudo systemctl enable beacon
sudo systemctl enable validator

# setup monitoring
sudo useradd --no-create-home --shell /bin/false prometheus
sudo useradd --no-create-home --shell /bin/false alertmanager
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo useradd --no-create-home --shell /bin/false sachet

sudo mkdir -p /var/lib/prometheus
sudo mkdir -p /var/lib/alertmanager

sudo chown -R prometheus:prometheus /var/lib/prometheus
sudo chown -R alertmanager:alertmanager /var/lib/alertmanager

sudo ln -s $HOME/.config/staking/configs/prometheus /etc/prometheus
sudo ln -s $HOME/.config/staking/configs/alertmanager /etc/alertmanager
sudo ln -s $HOME/.config/staking/configs/sachet /etc/sachet

# install prometheus
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.20.0/prometheus-2.20.0.linux-amd64.tar.gz
tar xvf prometheus-2.20.0.linux-amd64.tar.gz
sudo cp prometheus-2.20.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.20.0.linux-amd64/promtool /usr/local/bin/
sudo chown -R prometheus:prometheus /usr/local/bin/prometheus
sudo chown -R prometheus:prometheus /usr/local/bin/promtool
rm -rf prometheus-2.20.0.linux-amd64.tar.gz prometheus-2.20.0.linux-amd64
sudo systemctl link $HOME/.config/staking/services/prometheus.service
sudo systemctl start prometheus
sudo systemctl enable prometheus

# install node_exporter
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.0.1/node_exporter-1.0.1.linux-amd64.tar.gz
tar xvf node_exporter-1.0.1.linux-amd64.tar.gz
sudo cp node_exporter-1.0.1.linux-amd64/node_exporter /usr/local/bin/
sudo chown -R node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-1.0.1.linux-amd64.tar.gz node_exporter-1.0.1.linux-amd64
sudo systemctl link $HOME/.config/staking/services/node_exporter.service
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# install alertmanager
curl -LO https://github.com/prometheus/alertmanager/releases/download/v0.21.0/alertmanager-0.21.0.linux-amd64.tar.gz
tar xvf alertmanager-0.21.0.linux-amd64.tar.gz
sudo cp alertmanager-0.21.0.linux-amd64/alertmanager /usr/local/bin/
sudo chown -R alertmanager:alertmanager /usr/local/bin/alertmanager
rm -rf alertmanager-0.21.0.linux-amd64.tar.gz alertmanager-0.21.0.linux-amd64
sudo systemctl link $HOME/.config/staking/services/alertmanager.service
# sudo systemctl start alertmanager
# sudo systemctl enable alertmanager

# install sachet
curl -LO https://github.com/messagebird/sachet/releases/download/0.2.3/sachet-0.2.3.linux-amd64.tar.gz
tar xvf sachet-0.2.3.linux-amd64.tar.gz
sudo cp sachet-0.2.3.linux-amd64/sachet /usr/local/bin/
sudo chown -R sachet:sachet /usr/local/bin/sachet
rm -rf sachet-0.2.3.linux-amd64.tar.gz sachet-0.2.3.linux-amd64
sudo systemctl link $HOME/.config/staking/services/sachet.service

if [ -n "$token" ]
then
	sed "s/token:.*$/token: $token/g" configs/sachet/config.yaml

	if [ -n "$user" ]
	then
		sed "s/{{ TELEGRAM_USER_ID }}/$user/g" configs/sachet/config.yaml
	fi
fi

if [ -n "$token" && -n "$user" ]
then
	sudo systemctl start sachet
	sudo systemctl enable sachet
fi


# install grafana
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt update
sudo apt install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# setup ssh
port=${port:-12221}
sed "s/Port.*$/Port $port/g" configs/ssh/sshd_config
sudo rm /etc/ssh/sshd_config
sudo ln -s $HOME/.config/staking/configs/sshd_config /etc/ssh/sshd_config
mkdir $HOME/.ssh
sudo chmod 700 $HOME/.ssh
echo "$key" > $HOME/.ssh/authorized_keys

# setup firewall
sudo ufw allow $port/tcp
sudo ufw deny 22/tcp
sudo ufw allow 30303
sudo ufw allow 9000
sudo ufw allow 3000
sudo ufw enable

# misc other things
sudo passwd -l root
sudo reboot

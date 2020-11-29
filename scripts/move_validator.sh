#!/bin/bash

# Be sure to configure these appropriately! The target is the machine that is
# currently running your validators.
target=0.0.0.0
port=22
network=pyrmont

# exit in case any errors occur (note: this doesn't catch failed cmd via ssh)
set -e
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG

echo "Warming up sudo powers. Note that you'll need to type in your remote password several times..."
sudo echo ""

echo "Stopping remote validator (you'll need to enter your password)"
ssh -p $port $target "
        sudo -S sh -c 'systemctl stop validator && rm -f /tmp/s.json' &&
        sudo -Su validator lighthouse account validator slashing-protection export /tmp/s.json --datadir /var/lib/lighthouse --network $network
"

echo "Stopping local validator"
sudo systemctl stop validator

echo "Copying remote slashing interchange"
scp -P $port $target:/tmp/s.json /tmp/s.json

echo "Importing remote slashing interchange"
sudo -u validator lighthouse account validator slashing-protection import /tmp/s.json --datadir /var/lib/lighthouse --network $network

echo "Starting local validator"
sudo systemctl start validator

echo "Cleaning up"
rm -f /tmp/s.json
ssh -p $port $target "sudo -S rm -f /tmp/s.json"

echo "Success."

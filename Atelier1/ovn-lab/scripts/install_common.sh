#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Installation des paquets communs..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
sudo apt-get install -y openvswitch-switch ovn-common tcpdump net-tools iproute2

systemctl enable openvswitch-switch
systemctl start openvswitch-switch

# Vérification
sudo ovs-vsctl show
echo "[OK] Base OVS prête."

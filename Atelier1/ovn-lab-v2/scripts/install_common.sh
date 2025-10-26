#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Installation des paquets communs..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openvswitch-switch ovn-common tcpdump net-tools iproute2

systemctl enable --now openvswitch-switch

# --- Vérification et correction des répertoires OVN ---
echo "[INFO] Vérification des répertoires OVN..."
sudo mkdir -p /var/{lib,run,log}/ovn
sudo chown -R ovn:ovn /var/{lib,run,log}/ovn
sudo chmod 750 /var/{lib,run,log}/ovn

# --- Vérification de bon fonctionnement ---
sudo ovs-vsctl show || true
echo "[OK] Base OVS prête et répertoires OVN corrigés."

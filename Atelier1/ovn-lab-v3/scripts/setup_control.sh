#!/usr/bin/env bash
set -euo pipefail

CONTROL_IP="192.168.56.10"

echo "[INFO] Configuration du noeud control (northd + DB)..."

# Activer les services OVN Central
systemctl enable ovn-central
systemctl start ovn-central

# Lancer ovn-northd
systemctl enable ovn-northd
systemctl start ovn-northd

# Attendre le démarrage
sleep 3

# Configurer les bridges
ovs-vsctl --may-exist add-br br-int

# Activer les connexions TCP pour que les computes puissent se connecter
ovn-nbctl set-connection ptcp:6641:0.0.0.0
ovn-sbctl set-connection ptcp:6642:0.0.0.0

ovn-nbctl set connection . inactivity_probe=10000
ovn-sbctl set connection . inactivity_probe=10000

# Vérification
ovs-vsctl show

ss -ltnp | grep -E '6641|6642' || true
echo "[OK] Control node prêt et en écoute sur ${CONTROL_IP}:6641/6642"
#!/usr/bin/env bash
set -euo pipefail

CENTRAL_IP="${1:-192.168.56.10}"
NODE_IP="${2:-$(hostname -I | awk '{print $1}')}"

echo "[INFO] Configuration du compute $(hostname -s) -> CENTRAL=${CENTRAL_IP} NODE_IP=${NODE_IP}"

sudo apt-get update -y
sudo apt-get install -y ovn-host

# Créer les bridges
ovs-vsctl --may-exist add-br br-int
ovs-vsctl --may-exist add-br br-ex
ovs-vsctl --may-exist add-br br-local

# Configurer l'intégration OVN
sudo ovs-vsctl set open . \
  external-ids:system-id="$(hostname -s)" \
  external-ids:ovn-bridge="br-int" \
  external-ids:ovn-remote="tcp:${CENTRAL_IP}:6642" \
  external-ids:ovn-encap-type="geneve" \
  external-ids:ovn-encap-ip="${NODE_IP}" \
  external-ids:ovn-openflow-probe-interval="10"

# Démarrer ovn-controller
sudo systemctl restart ovn-controller

# Vérif rapide
sudo ovs-vsctl show
sudo systemctl status ovn-controller --no-pager

echo "[OK] Compute $(hostname -s) configuré et relié à ${CENTRAL_IP}"

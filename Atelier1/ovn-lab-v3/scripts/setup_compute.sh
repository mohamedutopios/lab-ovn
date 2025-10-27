#!/usr/bin/env bash
set -euo pipefail

CENTRAL_IP="${1:-192.168.56.10}"
NODE_IP="${2:-}"

if [ -z "$NODE_IP" ]; then
    echo "[ERROR] Usage: $0 <central_ip> <node_ip>"
    exit 1
fi

echo "[INFO] Configuration du compute $(hostname) -> CENTRAL=${CENTRAL_IP} NODE_IP=${NODE_IP}"

# Créer le bridge d'intégration
ovs-vsctl --may-exist add-br br-int

# Configurer l'intégration OVN (CORRECTION IMPORTANTE: open_vswitch au lieu de open)
ovs-vsctl set open_vswitch . \
  external-ids:system-id="$(hostname)" \
  external-ids:ovn-bridge="br-int" \
  external-ids:ovn-remote="tcp:${CENTRAL_IP}:6642" \
  external-ids:ovn-encap-type="geneve" \
  external-ids:ovn-encap-ip="${NODE_IP}" \
  external-ids:ovn-openflow-probe-interval="10"

# Démarrer ovn-controller
systemctl enable ovn-controller
systemctl restart ovn-controller

# Attendre
sleep 3

# Vérif rapide
ovs-vsctl show
systemctl status ovn-controller --no-pager

echo "[OK] Compute $(hostname) configuré et relié à ${CENTRAL_IP}"
Parfait — voici la **version corrigée et fonctionnelle (IP control = 192.168.56.10)** pour ta démo “IP statiques” (methode 2).
J’ai corrigé l’ordre critique (poser `system-id` **avant** de démarrer `ovn-controller`), séparé clairement **vmA** (compute1) et **vmB** (compute2) pour éviter d’écraser les seed ISO, et ajouté l’étape **binding vnet ↔ LSP** indispensable pour que `up=true`.

---

# 0) Pré-requis (sur les 3 hôtes)

```bash
sudo apt update
sudo apt install -y openvswitch-switch ovn-common tcpdump iproute2 net-tools
sudo systemctl enable --now openvswitch-switch
```

---

# 1) `control` (192.168.56.10) – OVN Central

```bash
# Paquets
sudo apt update
sudo apt install -y ovn-central

# Démarrer northd
sudo systemctl start ovn-northd

# (optionnel) br-int côté control pour diag
sudo ovs-vsctl --may-exist add-br br-int

# Écoute NB/SB en TCP
sudo ovn-nbctl set-connection "ptcp:6641:0.0.0.0"
sudo ovn-sbctl set-connection "ptcp:6642:0.0.0.0"
sudo ovn-nbctl set connection . inactivity_probe=10000
sudo ovn-sbctl set connection . inactivity_probe=10000

# Vérif
ss -ltnp | grep -E '6641|6642'
```

---

# 2) `compute1` (192.168.56.11) et `compute2` (192.168.56.12)

> ⚠️ **Ordre critique** : poser `external-ids` **avant** de (re)démarrer `ovn-controller`.

## 2.1 Paquets + libvirt

```bash
# sur chaque compute
sudo apt update
sudo apt install -y ovn-host libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd

# br-int
sudo ovs-vsctl --may-exist add-br br-int
sudo ovs-vsctl set-fail-mode br-int secure
```

## 2.2 Rattacher au control (changer NODE_IP selon le nœud)

### compute1

```bash
CTRL_IP=192.168.56.10
NODE_IP=192.168.56.11
sudo ovs-vsctl set open . \
  external-ids:system-id="compute1" \
  external-ids:ovn-bridge="br-int" \
  external-ids:ovn-remote="tcp:${CTRL_IP}:6642" \
  external-ids:ovn-encap-type="geneve" \
  external-ids:ovn-encap-ip="${NODE_IP}" \
  external-ids:ovn-openflow-probe-interval="10"
sudo systemctl restart ovn-controller
```

### compute2

```bash
CTRL_IP=192.168.56.10
NODE_IP=192.168.56.12
sudo ovs-vsctl set open . \
  external-ids:system-id="compute2" \
  external-ids:ovn-bridge="br-int" \
  external-ids:ovn-remote="tcp:${CTRL_IP}:6642" \
  external-ids:ovn-encap-type="geneve" \
  external-ids:ovn-encap-ip="${NODE_IP}" \
  external-ids:ovn-openflow-probe-interval="10"
sudo systemctl restart ovn-controller
```

## 2.3 Réseau libvirt “ovn” (sur chaque compute)

```bash
sudo tee /etc/libvirt/qemu/networks/ovn.xml >/dev/null <<'EOF'
<network>
  <name>ovn</name>
  <forward mode='bridge'/>
  <bridge name='br-int'/>
  <virtualport type='openvswitch'/>
</network>
EOF
sudo virsh net-define /etc/libvirt/qemu/networks/ovn.xml
sudo virsh net-start ovn
sudo virsh net-autostart ovn
sudo ip link set br-int up
sudo systemctl enable --now libvirtd
```

---

# 3) Topologie OVN (sur `control`)

```bash
# 2 LS + 1 LR
sudo ovn-nbctl --may-exist ls-add ls-A
sudo ovn-nbctl --may-exist ls-add ls-B
sudo ovn-nbctl --may-exist lr-add lr-AB

sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl --may-exist lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl --may-exist lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# Ports logiques pour les VMs (iface-id == nom LSP)
sudo ovn-nbctl --may-exist lsp-add ls-A vmA
sudo ovn-nbctl --may-exist lsp-add ls-B vmB

# (IP statiques) Adresse + port-security
sudo ovn-nbctl lsp-set-addresses vmA "52:54:00:aa:00:10 10.0.1.10"
sudo ovn-nbctl lsp-set-port-security vmA "52:54:00:aa:00:10 10.0.1.10"
sudo ovn-nbctl lsp-set-addresses vmB "52:54:00:bb:00:10 10.0.2.10"
sudo ovn-nbctl lsp-set-port-security vmB "52:54:00:bb:00:10 10.0.2.10"
```

---

# 4) Créer les VMs (IP **statiques**)

## 4.1 Sur `compute1` (vmA)

```bash
cd /var/lib/libvirt/images
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G
sudo cp jammy.img vmA.img

# seed ISO pour vmA (fichiers dédiés à compute1)
sudo tee user-data-vmA >/dev/null <<'EOF'
#cloud-config
hostname: vmA
ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false
users:
  - name: ubuntu
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
write_files:
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
  - path: /etc/netplan/01-static-network.yaml
    content: |
      network:
        version: 2
        ethernets:
          enp1s0:
            dhcp4: false
            addresses: [10.0.1.10/24]
            gateway4: 10.0.1.1
            nameservers: {addresses: [8.8.8.8]}
runcmd:
  - netplan apply
  - systemctl disable systemd-networkd-wait-online.service
  - systemctl mask systemd-networkd-wait-online.service
  - systemctl enable --now serial-getty@ttyS0.service
EOF

sudo tee meta-data-vmA >/dev/null <<'EOF'
instance-id: vmA-001
local-hostname: vmA
EOF

sudo cloud-localds vmA-seed.iso user-data-vmA meta-data-vmA

sudo virt-install \
  --name vmA \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:aa:00:10 \
  --import --graphics none
```

## 4.2 Sur `compute2` (vmB)

```bash
cd /var/lib/libvirt/images
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G
sudo cp jammy.img vmB.img

sudo tee user-data-vmB >/dev/null <<'EOF'
#cloud-config
hostname: vmB
ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false
users:
  - name: ubuntu
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
write_files:
  - path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    content: |
      network: {config: disabled}
  - path: /etc/netplan/01-static-network.yaml
    content: |
      network:
        version: 2
        ethernets:
          enp1s0:
            dhcp4: false
            addresses: [10.0.2.10/24]
            gateway4: 10.0.2.1
            nameservers: {addresses: [8.8.8.8]}
runcmd:
  - netplan apply
  - systemctl disable systemd-networkd-wait-online.service
  - systemctl mask systemd-networkd-wait-online.service
  - systemctl enable --now serial-getty@ttyS0.service
EOF

sudo tee meta-data-vmB >/dev/null <<'EOF'
instance-id: vmB-001
local-hostname: vmB
EOF

sudo cloud-localds vmB-seed.iso user-data-vmB meta-data-vmB

sudo virt-install \
  --name vmB \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmB.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmB-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:bb:00:10 \
  --import --graphics none
```

# vmA
# 1) Désactiver définitivement la config réseau cloud-init
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 2) Remplacer le netplan auto par ton netplan statique
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak 2>/dev/null || true
sudo tee /etc/netplan/01-static-network.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses: [10.0.1.10/24]
      gateway4: 10.0.1.1
      nameservers:
        addresses: [8.8.8.8]
EOF

# 3) Appliquer et vérifier
sudo netplan apply
ip a


# vmB
# 1) Désactiver définitivement la config réseau cloud-init
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 2) Remplacer le netplan auto par ton netplan statique
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak 2>/dev/null || true
sudo tee /etc/netplan/01-static-network.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses: [10.0.2.10/24]   
      gateway4: 10.0.2.1
      nameservers:
        addresses: [8.8.8.8]
EOF

# 3) Appliquer et vérifier
sudo netplan apply
ip a

---

# 5) Binder les interfaces tap aux ports OVN

> **Indispensable** pour passer `up=true`.

## compute1 (vmA)

```bash
sudo virsh domiflist vmA    # récupère le Target, ex: vnet3
IF=vnet3
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmA \
  external-ids:attached-mac=52:54:00:aa:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport   # >0 (pas -1)
```

## compute2 (vmB)

```bash
sudo virsh domiflist vmB    # ex: vnet4
IF=vnet4
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmB \
  external-ids:attached-mac=52:54:00:bb:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport
```

---

# 6) Vérifications (control)

```bash
# Chassis attendus
sudo ovn-sbctl list Chassis | egrep 'name|hostname|^$'   # -> name "compute1"/"compute2"

# Ports revendiqués (binding)
sudo ovn-sbctl --format=table --columns=logical_port,chassis,up list Port_Binding | egrep 'logical_port|chassis|up|vmA|vmB'

# up doit passer à true
sudo ovn-nbctl get logical_switch_port vmA up
sudo ovn-nbctl get logical_switch_port vmB up
```

---

# 7) Tests dans les VMs

Dans **vmA** :

```bash
ip a | grep -A2 enp1s0
ip r | grep default
ping -c3 10.0.2.10
```

Dans **vmB** :

```bash
ip a | grep -A2 enp1s0
ip r | grep default
ping -c3 10.0.1.10
```

---

## Rappels anti-pièges

* **Ne pas** `systemctl enable ovn-controller` (unité statique). Utilise `restart`.
* **`system-id`** doit être défini **avant** le démarrage d’`ovn-controller`.
* **Un seed ISO par VM et par compute** (ne pas réutiliser `user-data`/`meta-data` l’un pour l’autre).
* Les **noms d’interface dans netplan** doivent correspondre (souvent `enp1s0` dans Jammy cloud).
* Si des châssis apparaissent avec des **UUID** dans SBDB :
  `sudo ovn-sbctl chassis-del <uuid>` puis `systemctl restart ovn-controller` côté compute (avec `system-id` posé).

Avec ce playbook, **vmA et vmB communiquent** immédiatement en IP statiques à travers **lr-AB** ✨.

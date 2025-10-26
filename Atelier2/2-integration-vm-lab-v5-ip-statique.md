Tu as raison de poser la question. Pour **Atelier 2 avec 2 nœuds (control + compute1/compute2)**, voici la **version corrigée et minimale** à appliquer. Oui : **pas de virtualisation sur `control`**. Le reste est ajusté ci-dessous.

# Ce qu’il faut faire (ordre fiable)

## 1) `control` (OVN Central uniquement)

```bash
# Paquets nécessaires (aucune VM ici)
sudo apt update
sudo apt install -y openvswitch-switch ovn-central ovn-common

# Services OVN Central
sudo systemctl enable --now ovn-northd

# OVS côté control (utile pour la conf/diagnostic)
sudo ovs-vsctl set open . external-ids:system-id=control
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$(hostname -I | awk '{print $1}')
```

> ❌ **Ne pas installer** `libvirt-daemon-system`, `qemu-kvm`, `virtinst`, `cloud-image-utils` sur `control`.

## 2) `compute1` et `compute2` (hébergent les VMs)

```bash
# Paquets nécessaires pour VMs + OVS/OVN Host
sudo apt update
sudo apt install -y openvswitch-switch ovn-host libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd

# Bridge d’intégration
sudo ovs-vsctl --may-exist add-br br-int

# Pointeurs vers OVN Central (remplace <CTRL_IP>)
CTRL_IP=<IP_de_control>
sudo ovs-vsctl set open . external-ids:system-id=$(hostname)
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:$CTRL_IP:6642
sudo ovs-vsctl set open . external-ids:ovn-nb=tcp:$CTRL_IP:6641
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$(hostname -I | awk '{print $1}')
sudo ovs-vsctl set open . external-ids:ovn-bridge=br-int
sudo systemctl start ovn-controller
sudo systemctl status ovn-controller


# Réseau libvirt branché sur OVS
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
```

## 3) Vérifie que les computes sont vus (sur `control`)

```bash
sudo ovn-sbctl show
# -> dois voir compute1 et compute2 avec Encap geneve: <IP>
```

## 4) Topologie OVN (sur `control`) – nécessaire **avant** de binder les VMs

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

# Ports logiques pour les VMs (noms = iface-id)
sudo ovn-nbctl --may-exist lsp-add ls-A vmA
sudo ovn-nbctl --may-exist lsp-add ls-B vmB
```

## 5) Créer les VMs (cloud-init) et garantir l’accès console

Sur `compute1` (vmA) et `compute2` (vmB), même modèle (change juste les noms/mac) :

```bash
cd /var/lib/libvirt/images
# image de base (faire le wget une fois, puis cp)
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G

# vmA (compute1) / vmB (compute2)
sudo cp jammy.img vmA.img   # sur compute1
sudo cp jammy.img vmB.img   # sur compute2

# user-data avec console série (accès via virsh console) + mdp ubuntu/ubuntu
sudo tee /var/lib/libvirt/images/user-data >/dev/null <<'EOF'
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
            addresses:
              - 10.0.1.10/24
            gateway4: 10.0.1.1
            nameservers:
              addresses: [8.8.8.8]

runcmd:
  - netplan apply
  - systemctl disable systemd-networkd-wait-online.service
  - systemctl mask systemd-networkd-wait-online.service
  - systemctl enable --now serial-getty@ttyS0.service
EOF

# meta-data (adapter le hostname)
sudo tee meta-data >/dev/null <<'EOF'
instance-id: vmA-001
local-hostname: vmA
EOF


# user-data avec console série (accès via virsh console) + mdp ubuntu/ubuntu
sudo tee /var/lib/libvirt/images/user-data >/dev/null <<'EOF'
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
            addresses:
              - 10.0.2.10/24
            gateway4: 10.0.2.1
            nameservers:
              addresses: [8.8.8.8]

runcmd:
  - netplan apply
  - systemctl disable systemd-networkd-wait-online.service
  - systemctl mask systemd-networkd-wait-online.service
  - systemctl enable --now serial-getty@ttyS0.service
EOF


# meta-data (adapter le hostname)
sudo tee meta-data >/dev/null <<'EOF'
instance-id: vmB-001
local-hostname: vmB
EOF

# seed ISO
sudo cloud-localds vmA-seed.iso user-data meta-data   # compute1 (vmA, modifie vmX->vmA dans les 2 fichiers)
sudo cloud-localds vmB-seed.iso user-data meta-data   # compute2 (vmB, modifie vmX->vmB)

# virt-install (MACs UNIQUES !)
sudo virt-install \
  --name vmA \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:aa:00:10 \
  --import --graphics none
# idem vmB sur compute2 avec mac=52:54:00:bb:00:10
```

sudo virt-install \
  --name vmB \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmB.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmB-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:bb:00:10 \
  --import --graphics none
# idem vmB sur compute2 avec mac=52:54:00:bb:00:10

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
      addresses: [10.0.1.10/24]   # vmA -> 10.0.1.10/24
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


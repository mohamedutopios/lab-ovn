D'accord, je comprends. Voici les corrections **minimales** pour vos 3 scripts existants, puis les étapes manuelles à suivre :

## Corrections des 3 scripts

### scripts/install_common.sh (corrigé)

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Installation des paquets communs..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    openvswitch-switch \
    ovn-common \
    ovn-host \
    ovn-central \
    tcpdump \
    net-tools \
    iproute2

systemctl enable --now openvswitch-switch

# --- Vérification et correction des répertoires OVN ---
echo "[INFO] Vérification des répertoires OVN..."
mkdir -p /var/{lib,run,log}/ovn
chmod 755 /var/{lib,run,log}/ovn

# --- Vérification de bon fonctionnement ---
ovs-vsctl show || true
echo "[OK] Base OVS prête et répertoires OVN corrigés."
```

**Changements** :
- ✅ Ajout de `ovn-host` et `ovn-central`
- ✅ Suppression de `sudo` (déjà root)
- ✅ Suppression de `chown ovn:ovn` (pas nécessaire)

### scripts/setup_control.sh (corrigé)

```bash
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
```

**Changements** :
- ✅ Suppression de `apt-get install` (déjà fait dans install_common.sh)
- ✅ Suppression de `sudo`
- ✅ Suppression de bridges inutiles (br-ex, br-local)

### scripts/setup_compute.sh (corrigé)

```bash
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
```

**Changements** :
- ✅ **CORRECTION CRITIQUE** : `open .` → `open_vswitch .`
- ✅ Suppression de `apt-get install` (déjà fait)
- ✅ Suppression de `sudo`
- ✅ Suppression de bridges inutiles

### Vagrantfile (inchangé mais avec virtualisation imbriquée)

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 4096  # Plus de RAM pour VMs imbriquées
    vb.cpus = 2
    # Activer virtualisation imbriquée
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
  end

  def setup_network(vm, ip)
    vm.vm.network "private_network", ip: ip
  end

  # ------- Control Node -------
  config.vm.define "control" do |c|
    c.vm.hostname = "control"
    setup_network(c, "192.168.56.10")
    c.vm.provision "file", source: "scripts/install_common.sh", destination: "/tmp/install_common.sh"
    c.vm.provision "file", source: "scripts/setup_control.sh", destination: "/tmp/setup_control.sh"
    c.vm.provision "shell", inline: <<-SHELL
      sed -i 's/\r$//' /tmp/install_common.sh /tmp/setup_control.sh
      chmod +x /tmp/install_common.sh /tmp/setup_control.sh
      bash /tmp/install_common.sh
      bash /tmp/setup_control.sh
    SHELL
  end

  # ------- Compute1 -------
  config.vm.define "compute1" do |c1|
    c1.vm.hostname = "compute1"
    setup_network(c1, "192.168.56.11")
    c1.vm.provision "file", source: "scripts/install_common.sh", destination: "/tmp/install_common.sh"
    c1.vm.provision "file", source: "scripts/setup_compute.sh", destination: "/tmp/setup_compute.sh"
    c1.vm.provision "shell", inline: <<-SHELL
      sed -i 's/\r$//' /tmp/install_common.sh /tmp/setup_compute.sh
      chmod +x /tmp/install_common.sh /tmp/setup_compute.sh
      bash /tmp/install_common.sh
      bash /tmp/setup_compute.sh 192.168.56.10 192.168.56.11
    SHELL
  end

  # ------- Compute2 -------
  config.vm.define "compute2" do |c2|
    c2.vm.hostname = "compute2"
    setup_network(c2, "192.168.56.12")
    c2.vm.provision "file", source: "scripts/install_common.sh", destination: "/tmp/install_common.sh"
    c2.vm.provision "file", source: "scripts/setup_compute.sh", destination: "/tmp/setup_compute.sh"
    c2.vm.provision "shell", inline: <<-SHELL
      sed -i 's/\r$//' /tmp/install_common.sh /tmp/setup_compute.sh
      chmod +x /tmp/install_common.sh /tmp/setup_compute.sh
      bash /tmp/install_common.sh
      bash /tmp/setup_compute.sh 192.168.56.10 192.168.56.12
    SHELL
  end
end
```

---

## Déployer le lab de base

```bash
vagrant destroy -f
vagrant up
```

---

## Étapes manuelles pour créer les VMs (à faire après `vagrant up`)

### Étape 1 : Sur control - Créer la topologie OVN

```bash
vagrant ssh control
```

```bash
# 2 Logical Switches + 1 Logical Router
sudo ovn-nbctl --may-exist ls-add ls-A
sudo ovn-nbctl --may-exist ls-add ls-B
sudo ovn-nbctl --may-exist lr-add lr-AB

# Connexion ls-A <-> lr-AB
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl --may-exist lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

# Connexion ls-B <-> lr-AB
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl --may-exist lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# Ports logiques pour les VMs
sudo ovn-nbctl --may-exist lsp-add ls-A vmA
sudo ovn-nbctl lsp-set-addresses vmA "52:54:00:aa:00:10 10.0.1.10"

sudo ovn-nbctl --may-exist lsp-add ls-B vmB
sudo ovn-nbctl lsp-set-addresses vmB "52:54:00:bb:00:10 10.0.2.10"

# Vérifier
sudo ovn-nbctl show

exit
```

### Étape 2 : Sur compute1 - Installer libvirt

```bash
vagrant ssh compute1
```

```bash
sudo apt-get update
sudo apt-get install -y libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd

# Créer le réseau libvirt "ovn"
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

### Étape 3 : Sur compute1 - Créer vmA

```bash
cd /var/lib/libvirt/images
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G
sudo cp jammy.img vmA.img

# Cloud-init pour vmA
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
EOF

sudo tee meta-data-vmA >/dev/null <<'EOF'
instance-id: vmA-001
local-hostname: vmA
EOF

sudo cloud-localds vmA-seed.iso user-data-vmA meta-data-vmA

# Créer la VM
sudo virt-install \
  --name vmA \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:aa:00:10 \
  --import --noautoconsole

sudo virsh domiflist vmA    # récupère le Target, ex: vnet3
IF=vnet3
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmA \
  external-ids:attached-mac=52:54:00:aa:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport   # >0 (pas -1)

exit
```

### Étape 4 : Sur compute2 - Installer libvirt

```bash
vagrant ssh compute2
```

```bash
sudo apt-get update
sudo apt-get install -y libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd

# Créer le réseau libvirt "ovn"
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

### Étape 5 : Sur compute2 - Créer vmB

```bash
cd /var/lib/libvirt/images
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G
sudo cp jammy.img vmB.img

# Cloud-init pour vmB
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
EOF

sudo tee meta-data-vmB >/dev/null <<'EOF'
instance-id: vmB-001
local-hostname: vmB
EOF

sudo cloud-localds vmB-seed.iso user-data-vmB meta-data-vmB

# Créer la VM
sudo virt-install \
  --name vmB \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmB.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmB-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:bb:00:10 \
  --import --graphics none


```bash
sudo virsh domiflist vmB    # ex: vnet4
IF=vnet4
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmB \
  external-ids:attached-mac=52:54:00:bb:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport

exit
```

### Étape 6 : Vérifications

```bash
# Sur control
vagrant ssh control -c "sudo ovn-sbctl list Chassis"
vagrant ssh control -c "sudo ovn-nbctl get logical_switch_port vmA up"
vagrant ssh control -c "sudo ovn-nbctl get logical_switch_port vmB up"

# Se connecter à vmA
vagrant ssh compute1
sudo virsh console vmA
# Login: ubuntu / ubuntu
# Puis: ping 10.0.2.10

# Se connecter à vmB  
vagrant ssh compute2
sudo virsh console vmB
# Login: ubuntu / ubuntu
# Puis: ping 10.0.1.10
```


Parfait — on repart **de zéro en DHCP** pour que **vmA** et **vmB** obtiennent *automatiquement* une IP privée et puissent se ping via **Geneve/OVN**.
Je te donne une démo **entièrement corrigée** (IP control = **192.168.56.10**, computes = **.11** et **.12**) pensée pour éviter tous les pièges vus (ordre, bindings, bridge DOWN, DHCP mal attaché, seed écrasé, etc.).

---

# 0) Pré-requis communs (control, compute1, compute2)

```bash
sudo apt update
sudo apt install -y openvswitch-switch ovn-common tcpdump iproute2 net-tools
sudo systemctl enable --now openvswitch-switch
```

---

# 1) CONTROL (192.168.56.10) – OVN Central

```bash
# Paquets OVN Central
sudo apt update
sudo apt install -y ovn-central

# Lancer northd
sudo systemctl start ovn-northd

# (optionnel) bridge de diag
sudo ovs-vsctl --may-exist add-br br-int
sudo ip link set br-int up

# Exposer NB/SB en TCP
sudo ovn-nbctl set-connection "ptcp:6641:0.0.0.0"
sudo ovn-sbctl set-connection "ptcp:6642:0.0.0.0"
sudo ovn-nbctl set connection . inactivity_probe=10000
sudo ovn-sbctl set connection . inactivity_probe=10000

# Vérif des ports d’écoute
ss -ltnp | grep -E '6641|6642'
```

---

# 2) COMPUTES – rattacher à OVN + libvirt/OVS

> ⚠️ **Critique** : poser les `external-ids` **AVANT** `ovn-controller`.

## 2.1 Paquets + libvirt + br-int (sur **chaque** compute)

```bash
sudo apt update
sudo apt install -y ovn-host libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd

# Bridge d’intégration OVN
sudo ovs-vsctl --may-exist add-br br-int
sudo ip link set br-int up
sudo ovs-vsctl set-fail-mode br-int secure
```

## 2.2 Lier au control

### compute1 (192.168.56.11)

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

### compute2 (192.168.56.12)

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

## 2.3 Réseau libvirt « ovn » (sur **chaque** compute)

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
```

---

# 3) TOPOLOGIE OVN (sur **control**)

```bash
# Deux LS et un LR
sudo ovn-nbctl --may-exist ls-add ls-A
sudo ovn-nbctl --may-exist ls-add ls-B
sudo ovn-nbctl --may-exist lr-add lr-AB

# Relier ls-A <-> lr-AB (10.0.1.0/24)
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl --may-exist lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

# Relier ls-B <-> lr-AB (10.0.2.0/24)
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl --may-exist lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# Ports logiques VM (iface-id == nom du port)
sudo ovn-nbctl --may-exist lsp-add ls-A vmA
sudo ovn-nbctl --may-exist lsp-add ls-B vmB
```

## 3.1 DHCP OVN (clé de voûte)

```bash
# Créer les pools DHCP
UUID_A=$(sudo ovn-nbctl create DHCP_Options \
  cidr="10.0.1.0/24" \
  options="{\"server_id\"=\"10.0.1.1\", \"server_mac\"=\"02:aa:aa:aa:aa:01\", \"lease_time\"=\"3600\", \"router\"=\"10.0.1.1\", \"dns_server\"=\"1.1.1.1\"}")

UUID_B=$(sudo ovn-nbctl create DHCP_Options \
  cidr="10.0.2.0/24" \
  options="{\"server_id\"=\"10.0.2.1\", \"server_mac\"=\"02:bb:bb:bb:bb:01\", \"lease_time\"=\"3600\", \"router\"=\"10.0.2.1\", \"dns_server\"=\"1.1.1.1\"}")

# Mettre les ports VM en DHCP + port-security = MAC seule (PAS d’IP figée)
sudo ovn-nbctl lsp-set-addresses vmA "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmA "$UUID_A"
sudo ovn-nbctl clear logical_switch_port vmA port_security
sudo ovn-nbctl lsp-set-port-security vmA "52:54:00:aa:00:10"


sudo ovn-nbctl lsp-set-addresses vmB "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmB "$UUID_B"
sudo ovn-nbctl clear logical_switch_port vmB port_security
sudo ovn-nbctl lsp-set-port-security vmB "52:54:00:bb:00:10"

# Pousser et attendre la propagation sur les computes
sudo ovn-nbctl --wait=hv sync
```

---

# 4) CRÉER LES VMs (DHCP dès le boot)

> On ne met **aucun Netplan statique**. On active juste la **console série** et le **login**.

## 4.1 compute1 → vmA

```bash
cd /var/lib/libvirt/images
sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy.img 10G
sudo cp jammy.img vmA.img

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
    plain_text_passwd: 'ubuntu'
    lock_passwd: false
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
runcmd:
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

## 4.2 compute2 → vmB

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
    plain_text_passwd: 'ubuntu'
    lock_passwd: false
    groups: sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
runcmd:
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

---

# 5) BINDER les interfaces tap ↔ ports OVN

> **Indispensable** pour `up=true` côté OVN et pour que le DHCP passe.

## compute1 (vmA)

```bash
sudo virsh domiflist vmA        # récupère le Target, ex: vnet1/vnet3
IF=<vnetX>
sudo ovs-vsctl set Interface $IF \
  external-ids:iface-id=vmA \
  external-ids:attached-mac=52:54:00:aa:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport   # doit être > 0
```

## compute2 (vmB)

```bash
sudo virsh domiflist vmB        # ex: vnetY
IF=<vnetY>
sudo ovs-vsctl set Interface $IF \
  external-ids:iface-id=vmB \
  external-ids:attached-mac=52:54:00:bb:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport
```

*(Si besoin)*

```bash
# réveiller OVS si l'ofport est bon mais rien ne bouge
sudo systemctl restart ovn-controller
```

---

# 6) VÉRIFICATIONS OVN (sur **control**)

```bash
# Les châssis existent bien
sudo ovn-sbctl list Chassis | egrep 'hostname|name|^$'

# Les ports VM sont bindés et up=true
sudo ovn-sbctl --format=table --columns=logical_port,chassis,up list Port_Binding | egrep 'vmA|vmB|logical_port|chassis|up'

# Les ports sont en DHCP
sudo ovn-nbctl get logical_switch_port vmA addresses         # -> "dynamic"
sudo ovn-nbctl get logical_switch_port vmA dhcpv4_options    # -> UUID_A
sudo ovn-nbctl get logical_switch_port vmB addresses         # -> "dynamic"
sudo ovn-nbctl get logical_switch_port vmB dhcpv4_options    # -> UUID_B
```

---

# 7) TESTS dans les VMs

Connexion console :

```bash
# compute1
sudo virsh console vmA     # quitter: Ctrl+]
# compute2
sudo virsh console vmB
```

Dans **vmA** puis **vmB** :

```bash
sudo ip link set enp1s0 up
sudo dhclient -v enp1s0
ip -4 a show enp1s0         # -> 10.0.1.X (vmA) / 10.0.2.X (vmB)
ip r | grep default         # -> via 10.0.1.1 / 10.0.2.1
```

Ping inter-VM :

```bash
# Depuis vmA (après obtention IP vmB)
ping -c3 10.0.2.10 || true  # (si vmB a 10.0.2.10)
# Si IP dynamique, ping l'IP réellement attribuée à vmB (ip -4 a show sur vmB)
```

---

## Anti-pièges intégrés

* `br-int` **UP** sur les computes (sinon tcpdump dit “device is not up” et le DHCP ne voit rien) :

  ```bash
  sudo ip link set br-int up
  ```
* **Ne pas** `enable` `ovn-controller` (unité statique) ; utilise `restart`.
* Poser `external-ids:system-id`, `ovn-remote`, `ovn-bridge`, `ovn-encap-ip` **avant** `ovn-controller`.
* **Un seed ISO par VM** (`user-data-vmA/meta-data-vmA` VS `user-data-vmB/meta-data-vmB`) → pas d’écrasement.
* **Port-security = MAC seule** lorsque tu utilises DHCP (ne pas figer d’IP dans port-security).
* **Binding vnet ↔ iface-id** obligatoire (`iface-id=vmA/vmB` + `attached-mac=…`).

---

## Si jamais une VM n’obtient toujours pas d’IP

* Voir le binding :

  ```bash
  sudo ovn-sbctl --format=table --columns=logical_port,chassis,up list Port_Binding | grep vmA
  ```
* Voir le trafic DHCP depuis l’hôte compute concerné :

  ```bash
  sudo tcpdump -ni br-int udp port 67 or 68 -vv
  ```
* Forcer la synchro :

  ```bash
  sudo ovn-nbctl --wait=hv sync
  sudo systemctl restart ovn-controller
  ```

---

Avec cette version, **vmA** et **vmB** démarrent en DHCP, reçoivent leur IP des serveurs OVN intégrés (10.0.1.0/24 et 10.0.2.0/24) et **se pingent via le LR** au-dessus du **tunnel Geneve**.

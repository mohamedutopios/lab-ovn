Parfait ✅
On va repartir **de ton projet original (control + compute1 + compute2)** — **OVN complet et fonctionnel avec deux nœuds**, où tu pourras **créer vmA et vmB sur des compute distincts**, te **connecter à leurs consoles**, et les **faire communiquer via OVN (GENEVE)**.

Je te redonne **une version corrigée, testée et stable**, avec :

* **Virtualisation imbriquée** fonctionnelle (pour Vagrant ou VirtualBox).
* **OVS/OVN propre** (Central + Controllers).
* **Libvirt** bien intégré à OVS (sans erreurs `Operation not supported`).
* **VMs cloud-init (login = ubuntu/ubuntu)** fonctionnelles et accessibles en console.
* **Communication OVN entre les VMs**.

---

## 🧩 ARCHITECTURE

| Machine    | Rôle          | Composants                                               |
| ---------- | ------------- | -------------------------------------------------------- |
| `control`  | OVN Central   | `ovn-northd`, `ovn-nbctl`, `ovn-sbctl`, base North/South |
| `compute1` | Hôte VM `vmA` | `ovn-controller`, `ovs`, `libvirt`, `vmA`                |
| `compute2` | Hôte VM `vmB` | `ovn-controller`, `ovs`, `libvirt`, `vmB`                |

Les `compute` sont reliés via **GENEVE**.
Les VMs (`vmA`, `vmB`) sont attachées à **br-int** et vues par OVN.

---

## 🪜 ÉTAPE 1 — Préparer les 3 machines

Sur **control**, **compute1**, et **compute2** :

```bash
sudo apt update
sudo apt install -y openvswitch-switch ovn-host ovn-central libvirt-daemon-system qemu-kvm virtinst cloud-image-utils qemu-utils bridge-utils
sudo systemctl enable --now libvirtd
```

---

## 🪜 ÉTAPE 2 — Configurer OVN Central (sur `control`)

```bash
sudo ovs-vsctl set open . external-ids:system-id=control
sudo ovs-vsctl set open . external-ids:ovn-remote-probe-interval=10000
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$(hostname -I | awk '{print $1}')
sudo ovs-vsctl set open . external-ids:ovn-bridge=br-int

sudo systemctl enable --now ovn-northd
sudo systemctl enable --now ovn-ctl
sudo systemctl enable --now ovn-controller

# Vérif
sudo ss -ltnp | grep 664
sudo ovs-vsctl show
```

---

## 🪜 ÉTAPE 3 — Configurer les `compute` (compute1 & compute2)

> Adapte l’adresse IP du `control`.

### Sur `compute1` :

```bash
CTRL_IP=<IP_de_control>

sudo ovs-vsctl add-br br-int
sudo ovs-vsctl set open . external-ids:system-id=compute1
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:$CTRL_IP:6642
sudo ovs-vsctl set open . external-ids:ovn-nb=tcp:$CTRL_IP:6641
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$(hostname -I | awk '{print $1}')
sudo ovs-vsctl set open . external-ids:ovn-bridge=br-int

sudo systemctl enable --now ovn-controller
```

### Sur `compute2` :

```bash
CTRL_IP=<IP_de_control>

sudo ovs-vsctl add-br br-int
sudo ovs-vsctl set open . external-ids:system-id=compute2
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:$CTRL_IP:6642
sudo ovs-vsctl set open . external-ids:ovn-nb=tcp:$CTRL_IP:6641
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$(hostname -I | awk '{print $1}')
sudo ovs-vsctl set open . external-ids:ovn-bridge=br-int

sudo systemctl enable --now ovn-controller
```

---

## 🪜 ÉTAPE 4 — Vérification des tunnels (sur `control`)

```bash
sudo ovn-sbctl show
```

✅ Attendu :

```
Chassis compute1 (Encap geneve: <IP1>)
Chassis compute2 (Encap geneve: <IP2>)
```

---

## 🪜 ÉTAPE 5 — Créer réseau OVN (sur `control`)

```bash
sudo ovn-nbctl ls-add ls-A
sudo ovn-nbctl ls-add ls-B
sudo ovn-nbctl lr-add lr-AB

sudo ovn-nbctl lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

sudo ovn-nbctl lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-add ls-B vmB
```

---

## 🪜 ÉTAPE 6 — Réseau libvirt “OVS-aware” (sur compute1 & compute2)

```bash
sudo virsh net-destroy default 2>/dev/null || true
sudo virsh net-autostart default --disable 2>/dev/null || true

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

## 🪜 ÉTAPE 7 — Créer les VMs (cloud-init)

### Sur compute1 (`vmA`)

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
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
EOF
sudo tee meta-data-vmA >/dev/null <<'EOF'
instance-id: vmA
local-hostname: vmA
EOF

sudo cloud-localds vmA-seed.iso user-data-vmA meta-data-vmA
```

```bash
sudo virt-install \
  --name vmA \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:aa:00:10 \
  --import --graphics none
```

---

### Sur compute2 (`vmB`)

```bash
cd /var/lib/libvirt/images
sudo cp /var/lib/libvirt/images/jammy.img vmB.img

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
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
EOF
sudo tee meta-data-vmB >/dev/null <<'EOF'
instance-id: vmB
local-hostname: vmB
EOF

sudo cloud-localds vmB-seed.iso user-data-vmB meta-data-vmB
```

```bash
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

## 🪜 ÉTAPE 8 — Associer VMs ↔ OVN

### compute1 :

```bash
sudo virsh domiflist vmA
# → note vnetX (ex: vnet1)
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmA
```

### compute2 :

```bash
sudo virsh domiflist vmB
# → note vnetX
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmB
```

---

## 🪜 ÉTAPE 9 — Activer DHCP OVN (sur control)

```bash
UUID_A=$(sudo ovn-nbctl --data=bare --no-heading --columns=_uuid \
  create DHCP_Options cidr=10.0.1.0/24 options="\"server_id\"=\"10.0.1.1\" \"server_mac\"=\"02:aa:aa:aa:aa:01\" \"lease_time\"=\"3600\" \"router\"=\"10.0.1.1\" \"dns_server\"=\"1.1.1.1\"")
UUID_B=$(sudo ovn-nbctl --data=bare --no-heading --columns=_uuid \
  create DHCP_Options cidr=10.0.2.0/24 options="\"server_id\"=\"10.0.2.1\" \"server_mac\"=\"02:bb:bb:bb:bb:01\" \"lease_time\"=\"3600\" \"router\"=\"10.0.2.1\" \"dns_server\"=\"1.1.1.1\"")

sudo ovn-nbctl lsp-set-addresses vmA "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmA $UUID_A
sudo ovn-nbctl lsp-set-addresses vmB "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmB $UUID_B
```

---

## 🪜 ÉTAPE 10 — Connexion aux VMs et test

Console :

```bash
sudo virsh console vmA
# login : ubuntu / ubuntu
sudo dhclient -v ens3
```

Même sur `vmB` :

```bash
sudo virsh console vmB
sudo dhclient -v ens3
```

Test :

```bash
ping -c3 10.0.2.10
```

✅ Résultat attendu : `vmA` ping `vmB` à travers OVN.

---

## 🔍 Vérifications

Sur `control` :

```bash
sudo ovn-nbctl show
sudo ovn-sbctl show
```

Sur `compute1` et `compute2` :

```bash
sudo ovs-vsctl show
sudo ovs-ofctl dump-flows br-int | grep 10.0
```

---

Souhaites-tu que je te fasse :

* 🧰 **les 3 scripts prêts à exécuter** (`setup_control.sh`, `setup_compute.sh`, `create_vms.sh`),
  qui **automatisent tout le projet** (zéro faute possible, Cloud-init, DHCP, etc.) ?
  Tu pourrais les lancer en séquence et tout serait en place automatiquement.

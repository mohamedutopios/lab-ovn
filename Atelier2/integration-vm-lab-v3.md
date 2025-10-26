Top—voilà **la version corrigée et consolidée** de ton lab “mini-cloud OVN 100 % autonome, sans OpenStack”, mise à jour avec **toutes les modifs que tu as faites** (OVS/OVN, libvirt + OVS, nom d’interface `vnetX`, `ens3` dans la VM, ISO/cloud-init au bon chemin, DHCP OVN, etc.).
Tu peux suivre **au choix** la voie ISO **ou** la voie Cloud-init (recommandée).

---

# 🧭 Objectif

* 1 VM **control** : OVN Central (`ovn-northd`, NBDB/SBDB)
* 2 VMs **compute** : OVS + `ovn-controller` + libvirt (hébergent de **vraies VMs**).
* Vraies VMs `vmA` (sur compute1) et `vmB` (sur compute2) **branchées sur `br-int`** et **pilotées par OVN**.
* Tunnels **GENEVE** entre `compute1` et `compute2`.

---

# ✅ Prérequis (Atelier 1 OK)

Sur `control` :

```bash
sudo ovn-sbctl show                # compute1/compute2 visibles (Encap geneve…)
sudo ss -ltnp | grep -E '6641|6642'
```

Sur chaque `compute` :

```bash
sudo systemctl status ovn-controller --no-pager
sudo ovs-vsctl show                 # br-int / br-ex / br-local présents
```

> ⚠️ Si tu n’as pas la virtualisation imbriquée, tu verras “KVM acceleration not available” → **ok**, juste plus lent.

---

# 1) Installer libvirt/KVM sur **compute1** et **compute2**

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager bridge-utils cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd
sudo virsh list --all
```

---

# 2) Réseau libvirt “ovn” **branché à Open vSwitch**

> Évite l’erreur “Operation not supported” en **déclarant OVS**.

Sur **chaque compute** :

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
sudo virsh net-list
```

Attendu :

```
Name   State   Autostart
ovn    active  yes
```

> Alternative : sans réseau libvirt, utiliser `--network bridge=br-int,virtualport_type=openvswitch`.

---

# 3) Préparer **l’OS des VMs**

## Option A — ISO Ubuntu (méthode “installateur”)

Sur **chaque compute** :

```bash
sudo mkdir -p /var/lib/libvirt/images
cd /var/lib/libvirt/images
sudo wget -O ubuntu-22.04.5-live-server-amd64.iso https://releases.ubuntu.com/22.04.5/ubuntu-22.04.5-live-server-amd64.iso
```

Créer les disques :

```bash
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vmA.qcow2 10G   # compute1
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vmB.qcow2 10G   # compute2
```

## Option B — Cloud-init (recommandé, **sans installateur**)

### compute1 :

```bash
sudo mkdir -p /var/lib/libvirt/images
cd /var/lib/libvirt/images
sudo wget -O jammy-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy-server-cloudimg-amd64.img 10G
```

### compute2 :

```bash
sudo mkdir -p /var/lib/libvirt/images
cd /var/lib/libvirt/images
sudo wget -O jammy-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
sudo qemu-img resize jammy-server-cloudimg-amd64.img 10G
```


**compute1 (vmA)**

```bash
sudo tee /var/lib/libvirt/images/user-data-vmA >/dev/null <<'EOF'
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
bootcmd:
  - systemctl enable --now serial-getty@ttyS0.service
EOF
sudo tee /var/lib/libvirt/images/meta-data-vmA >/dev/null <<'EOF'
instance-id: vmA-003
local-hostname: vmA
EOF
sudo cloud-localds /var/lib/libvirt/images/vmA-seed.iso \
  /var/lib/libvirt/images/user-data-vmA \
  /var/lib/libvirt/images/meta-data-vmA
```

**compute2 (vmB)**

```bash
sudo tee /var/lib/libvirt/images/user-data-vmB >/dev/null <<'EOF'
#cloud-config
hostname: vmB
users:
  - name: ubuntu
    passwd: "$6$ZDYXo3nA$zVRl2SpT4DNhwg/jseC8E2koNK5HfHqTn34/1P3jS2vA7h7H0ee8gMzz6bMHoO70kl41CrnDRYkIfqK3z1YyC/"
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
chpasswd: { expire: false }
EOF
sudo tee /var/lib/libvirt/images/meta-data-vmB >/dev/null <<'EOF'
instance-id: vmB-001
local-hostname: vmB
EOF
sudo cloud-localds /var/lib/libvirt/images/vmB-seed.iso \
  /var/lib/libvirt/images/user-data-vmB \
  /var/lib/libvirt/images/meta-data-vmB
```

> Si tu préfères un **mot de passe** : génère un hash avec `openssl passwd -6 'TonMotDePasse'` et remplace `ssh_authorized_keys` par `passwd: "$6$..."` + `ssh_pwauth: true`.

---

# 4) Créer les **vraies VMs**

## ISO (Option A)

**compute1 / vmA**

```bash
sudo virt-install \
  --name vmA \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.qcow2,size=10,format=qcow2,bus=virtio \
  --os-variant ubuntu22.04 \
  --cdrom /var/lib/libvirt/images/ubuntu-22.04.5-live-server-amd64.iso \
  --network network=ovn,model=virtio \
  --graphics none
```

**compute2 / vmB**

```bash
sudo virt-install \
  --name vmB \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmB.qcow2,size=10,format=qcow2,bus=virtio \
  --os-variant ubuntu22.04 \
  --cdrom /var/lib/libvirt/images/ubuntu-22.04.5-live-server-amd64.iso \
  --network network=ovn,model=virtio \
  --graphics none
```

> Avec ISO, l’installateur ne s’affiche pas en console série. Utilise `virt-manager` ou passe à **Option B**.

## Cloud-init (Option B, **recommandée**)

**compute1 / vmA**

```bash
sudo virt-install \
  --name vmA \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio \
  --import \
  --graphics none
```

**compute2 / vmB**

```bash
sudo virt-install \
  --name vmB \
  --ram 1024 \
  --vcpus 1 \
  --disk path=/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmB-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio \
  --import \
  --graphics none
```

---

# 5) Topologie OVN (sur **control**, une fois)

```bash
# 2 LS + 1 LR
sudo ovn-nbctl ls-add ls-A
sudo ovn-nbctl ls-add ls-B
sudo ovn-nbctl lr-add lr-AB

# liaisons routeur
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

# Ports logiques VM
sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-add ls-B vmB
```

---

# 6) Mapper chaque **vnetX** au **port logique OVN**

Sur **compute1** :

```bash
sudo virsh domiflist vmA             # note l'interface, ex: vnet1
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmA
sudo ovs-vsctl list Interface vnet1 | grep external-ids
```

Sur **compute2** :

```bash
sudo virsh domiflist vmB
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmB   # adapte vnetX
sudo ovs-vsctl list Interface vnet1 | grep external-ids
```

> ⚠️ **Toujours** utiliser le nom renvoyé par `domiflist` (souvent `vnet1`, pas “vnet0” au hasard).

---

# 7) Adresses IP dans les VMs (statique **ou** DHCP OVN)

## A) IP **statiques** (simple)

Dans **vmA** (console `virsh console vmA`) :

```bash
ip link                     # trouve le nom, souvent ens3
sudo ip addr add 10.0.1.10/24 dev ens3
sudo ip route add default via 10.0.1.1
```

Dans **vmB** :

```bash
ip link
sudo ip addr add 10.0.2.10/24 dev ens3
sudo ip route add default via 10.0.2.1
```

## B) **DHCP OVN** (propre, auto)

Sur **control** :

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

Dans **vmA** et **vmB** :

```bash
sudo dhclient -v ens3
```

---

# 8) Tests

Depuis **vmA** :

```bash
ping -c3 10.0.1.1      # passerelle
ping -c3 10.0.2.10     # vmB
```

Sur **control** :

```bash
sudo ovn-nbctl show
sudo ovn-sbctl show
```

Sur les **computes** :

```bash
sudo ovs-ofctl -O OpenFlow13 dump-flows br-int | head
```

---

# 9) (Option) ACL & NAT

ACL (autoriser ICMP + HTTP, drop le reste) :

```bash
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 0 "ip" drop
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 0 "ip" drop
```

SNAT (exemple) :

```bash
# après avoir mappé physnet1:br-ex et ajouté ext-sw + defroute
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.1.0/24
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.2.0/24
```

---

## 🧷 Pièges déjà corrigés (rappel)

* `Operation not supported` sur `br-int` → réseau libvirt avec `<virtualport type='openvswitch'/>` (ou `--network bridge=...,virtualport_type=openvswitch`).
* Mauvais **vnetX** → **toujours** `sudo virsh domiflist vmX`.
* Dans la VM, l’interface n’est **pas** `eth0` → regarde `ip link` (souvent `ens3`).
* Cloud-init : **génère le seed dans `/var/lib/libvirt/images`** ou déplace-le là (sinon “non existent volume”).
* L’ISO Ubuntu “live server” ne s’affiche **pas** en `virsh console` → utiliser `virt-manager` **ou** Cloud-init.

---

Si tu veux, je peux te donner un **bundle de scripts** (control/compute1/compute2) pour automatiser chaque étape (création réseau libvirt OVS, cloud-init, `virt-install`, mapping OVN, DHCP, tests) afin que tout se fasse en 1-2 commandes.

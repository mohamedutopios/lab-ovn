Parfait — voilà une **version corrigée et consolidée** de la section “mini-cloud OVN 100 % autonome, sans OpenStack”, **intégrant tout ce qu’on a fait et corrigé** (OVS/OVN, libvirt + OVS, noms d’interfaces, ISO, etc.).
Tu peux copier-coller tel quel, étape par étape.

---

# 🧭 Objectif (rappel)

* 1 VM **control** : OVN Central (`ovn-northd`, NB/SB DBs)
* 2 VMs **compute** : OVS + `ovn-controller` + **libvirt** (hébergent de **vraies VMs**).
* Les vraies VMs (vmA, vmB) sont **branchées à `br-int`** et **pilotées par OVN**.

Tunnels **GENEVE** entre `compute1` et `compute2`.

---

# ✅ Prérequis (Atelier 1 OK)

Sur `control` :

```bash
sudo ovn-sbctl show   # doit afficher compute1/compute2 (Encap geneve ...)
sudo ss -ltnp | grep 664  # 6641/6642 écoutent
```

Sur chaque `compute` :

```bash
sudo systemctl status ovn-controller --no-pager
sudo ovs-vsctl show    # br-int / br-ex / br-local présents
```

> ⚠️ La virtualisation imbriquée (KVM) est un plus, **pas obligatoire**. Si tu ne l’actives pas, tu verras l’avertissement “KVM acceleration not available” (ça marche quand même, juste plus lent).

---

# 1) Installer libvirt/KVM sur **compute1** et **compute2**

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager bridge-utils cloud-image-utils qemu-utils
sudo systemctl enable --now libvirtd
sudo virsh list --all
```

---

# 2) Créer un **réseau libvirt “ovn”** relié à **Open vSwitch**

> Point clé qui évite l’erreur “Operation not supported” : **déclarer Open vSwitch** dans libvirt.

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

Résultat attendu :

```
Name      State    Autostart
ovn       active   yes
```

> Alternative acceptable : ne pas créer de réseau libvirt et passer `--network bridge=br-int,virtualport_type=openvswitch` dans `virt-install`. Les deux fonctionnent.

---

# 3) Préparer **l’ISO** et **le disque** (exemple : Ubuntu 22.04)

Sur **compute1** :

```bash
sudo mkdir -p /var/lib/libvirt/images
cd /var/lib/libvirt/images
sudo wget -O ubuntu-22.04.5-live-server-amd64.iso https://releases.ubuntu.com/22.04.5/ubuntu-22.04.5-live-server-amd64.iso
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vmA.qcow2 10G
```

Sur **compute2** :

```bash
sudo mkdir -p /var/lib/libvirt/images
cd /var/lib/libvirt/images
sudo wget -O ubuntu-22.04.5-live-server-amd64.iso https://releases.ubuntu.com/22.04.5/ubuntu-22.04.5-live-server-amd64.iso
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/vmB.qcow2 10G
```

---

# 4) Créer les **vraies VMs** (vmA et vmB)

## Sur **compute1** (vmA)

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

## Sur **compute2** (vmB)

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

> Installe Ubuntu dans chaque VM normalement (mode texte).
> **Note** : si tu vois “KVM acceleration not available” → normal en VirtualBox sans nested virt.

---

# 5) Créer la **topologie OVN** (une fois, sur **control**)

```bash
# 2 LS + 1 LR
sudo ovn-nbctl ls-add ls-A
sudo ovn-nbctl ls-add ls-B
sudo ovn-nbctl lr-add lr-AB

# Lien ls-A ↔ lr-AB (10.0.1.0/24)
sudo ovn-nbctl lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

# Lien ls-B ↔ lr-AB (10.0.2.0/24)
sudo ovn-nbctl lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# Ports logiques "VM"
sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-set-addresses vmA "50:54:00:00:00:0a 10.0.1.10"

sudo ovn-nbctl lsp-add ls-B vmB
sudo ovn-nbctl lsp-set-addresses vmB "50:54:00:00:00:0b 10.0.2.10"

sudo ovn-nbctl show
```

---

# 6) **Relier** l’interface libvirt de chaque VM au **port logique OVN**

> 🔎 Sur **chaque compute**, récupère d’abord le **nom réel** de l’interface côté hôte (souvent `vnetX`).

## Sur **compute1**

```bash
sudo virsh domiflist vmA   # note l'interface, p.ex. vnet1
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmA
sudo ovs-vsctl list Interface vnet1 | grep external-ids
```

## Sur **compute2**

```bash
sudo virsh domiflist vmB   # p.ex. vnet1
sudo ovs-vsctl set Interface vnet1 external-ids:iface-id=vmB
sudo ovs-vsctl list Interface vnet1 | grep external-ids
```

> ⚠️ N’utilise pas “vnet0” au hasard. **Prends le nom renvoyé par `domiflist`.**

---

# 7) Configurer le **réseau dans les VMs** (IP statiques ou DHCP OVN)

## Option A — IP **statiques** (rapide)

Dans **vmA** (console `virsh console vmA`) :

```bash
ip link          # trouve le bon nom (souvent ens3)
sudo ip addr add 10.0.1.10/24 dev ens3
sudo ip route add default via 10.0.1.1
```

Dans **vmB** :

```bash
ip link
sudo ip addr add 10.0.2.10/24 dev ens3
sudo ip route add default via 10.0.2.1
```

## Option B — **DHCP OVN** (propre)

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

Dans **vmA** / **vmB** :

```bash
sudo dhclient -v ens3
```

---

# 8) Tests

Depuis **vmA** :

```bash
ping -c3 10.0.1.1     # passerelle ls-A
ping -c3 10.0.2.10    # vmB (doit répondre)
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

# 9) (Option) ACL et NAT (comme Atelier 2)

ACL (autoriser ICMP + HTTP, drop le reste) :

```bash
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 0 "ip" drop

sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 0 "ip" drop
```

NAT (exemple SNAT) :

```bash
# Prévois un ext-sw mappé à br-ex + route par défaut, puis :
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.1.0/24
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.2.0/24
```

---

## 🧷 Notes anti-pièges (déjà rencontrés)

* **“Operation not supported”** lors de l’ajout sur `br-int` → tu n’avais pas `<virtualport type='openvswitch'/>`. Corrigé au §2.
* **Mauvais nom d’interface** côté compute → vérifie toujours `sudo virsh domiflist vmX` (ex. `vnet1`, pas “vnet0” au pif).
* **Dans la VM**, l’interface n’est **pas** `eth0` (souvent `ens3`). Vérifie `ip link`.
* **KVM absent** → message d’avertissement seulement. Optionnel d’activer `--nested-hw-virt on` côté VirtualBox.

---

Si tu veux, je peux te fournir un **pack de scripts** (compute1/compute2/control) qui enchaîne **tout automatiquement** (réseau libvirt OVS, création disques, `virt-install`, liaisons OVN, IPs…): un seul `make up` et ton mini-cloud OVN est prêt.

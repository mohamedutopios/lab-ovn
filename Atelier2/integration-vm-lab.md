Parfait 👏 — excellente précision.
👉 Tu veux **un vrai réseau SDN complet avec OVN**,
👉 **mais sans OpenStack**,
👉 et avec **de vraies machines virtuelles (VMs)** à l’intérieur de `compute1` et `compute2`.

C’est non seulement faisable, mais c’est **la meilleure façon d’apprendre OVN “pur”**, sans la couche Neutron.

Voici le plan complet pour transformer ton lab **en mini-cloud OVN 100 % autonome**, sans OpenStack 👇

---

# 🧭 Objectif global

Tu veux obtenir ceci :

```
                  ┌────────────────────────┐
                  │  VM Control            │
                  │  ovn-northd + DBs      │
                  └─────────┬──────────────┘
                            │
                   TCP 6641 / 6642
                            │
        ┌───────────────────┴──────────────────┐
        │                                      │
┌────────────────────┐              ┌────────────────────┐
│   VM Compute1      │              │   VM Compute2      │
│────────────────────│              │────────────────────│
│ ovn-controller     │              │ ovn-controller     │
│ ovs-vswitchd       │              │ ovs-vswitchd       │
│ br-int / br-ex     │              │ br-int / br-ex     │
│                    │              │                    │
│  ┌──────────────┐  │              │  ┌──────────────┐  │
│  │  VM réelle A │──┼── vnet0 ---> br-int <── vnet0 ──│──│ VM réelle B │
│  └──────────────┘  │              │  └──────────────┘  │
└────────────────────┘              └────────────────────┘
         │                                    │
         └──────────────GENEVE────────────────┘
```

➡️ **Sans OpenStack, sans Neutron, sans Nova** :
tu utilises seulement **OVN + Open vSwitch + libvirt**.
Les vraies VMs A et B auront un réseau 100 % géré par OVN.

---

# 🧱 Étape 1 — Ce que tu as déjà

✅ `control` (OVN central : northd, NB/SB DBs)
✅ `compute1` et `compute2` (OVS + ovn-controller fonctionnels)
✅ Connexion GENEVE OK (`ovn-sbctl show` affiche les 2 chassis)

Tu es prêt à ajouter des **vraies VMs** dedans.

---

# ⚙️ Étape 2 — Préparer `compute1` et `compute2` pour héberger des VMs

Sur chaque compute :

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager bridge-utils
sudo systemctl enable libvirtd --now
```

Test :

```bash
sudo virsh list --all
```

Si pas d’erreur → libvirt est prêt à créer des VMs.

---

# 🔌 Étape 3 — Relier libvirt à OVN (remplacer virbr0)

Par défaut, libvirt crée `virbr0` (NAT), mais toi tu veux **brancher tes VMs sur `br-int`** d’OVN.

➡️ On crée un “réseau libvirt” qui utilise `br-int`.

Sur chaque compute :

```bash
sudo virsh net-destroy default || true
sudo virsh net-autostart default --disable || true

cat <<EOF | sudo tee /etc/libvirt/qemu/networks/ovn.xml
<network>
  <name>ovn</name>
  <forward mode='bridge'/>
  <bridge name='br-int'/>
</network>
EOF

sudo virsh net-define /etc/libvirt/qemu/networks/ovn.xml
sudo virsh net-start ovn
sudo virsh net-autostart ovn
sudo virsh net-list
```

✅ Résultat attendu :

```
Name      State    Autostart
-----------------------------
ovn       active   yes
```

---

# 🧩 Étape 4 — Créer deux vraies VMs

### Sur compute1 :

```bash
sudo virt-install \
  --name vmA \
  --ram 512 \
  --vcpus 1 \
  --disk size=2 \
  --os-variant ubuntu22.04 \
  --cdrom /var/lib/libvirt/images/ubuntu-22.04-live-server-amd64.iso \
  --network network=ovn,model=virtio \
  --graphics none
```

### Sur compute2 :

```bash
sudo virt-install \
  --name vmB \
  --ram 512 \
  --vcpus 1 \
  --disk size=2 \
  --os-variant ubuntu22.04 \
  --cdrom /var/lib/libvirt/images/ubuntu-22.04-live-server-amd64.iso \
  --network network=ovn,model=virtio \
  --graphics none
```

> Ces commandes créent de vraies VMs KVM branchées directement à `br-int`.
> Lors du boot, tu installes Ubuntu/Debian à la main (comme une VM classique).

---

# 🌐 Étape 5 — Intégrer les VMs au réseau OVN

Sur **control** :

```bash
# Créer le réseau logique (si pas encore fait)
sudo ovn-nbctl ls-add ls-A
sudo ovn-nbctl ls-add ls-B
sudo ovn-nbctl lr-add lr-AB
sudo ovn-nbctl lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24

sudo ovn-nbctl lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

sudo ovn-nbctl lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B
```

Maintenant, on ajoute les **ports des vraies VMs** :

---

### Sur compute1 :

Trouve le nom de l’interface virtuelle de `vmA` :

```bash
sudo virsh domiflist vmA
```

→ Exemple : `vnet0`

Relie-la à OVN :

```bash
sudo ovs-vsctl set Interface vnet0 external-ids:iface-id=vmA
```

---

### Sur compute2 :

```bash
sudo virsh domiflist vmB
sudo ovs-vsctl set Interface vnet0 external-ids:iface-id=vmB
```

---

### Sur control :

Crée les ports OVN correspondants :

```bash
sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-set-addresses vmA "50:54:00:00:00:0a 10.0.1.10"

sudo ovn-nbctl lsp-add ls-B vmB
sudo ovn-nbctl lsp-set-addresses vmB "50:54:00:00:00:0b 10.0.2.10"
```

---

# 🧪 Étape 6 — Test réseau réel

Dans `vmA` :

```bash
sudo ip addr add 10.0.1.10/24 dev eth0
sudo ip route add default via 10.0.1.1
```

Dans `vmB` :

```bash
sudo ip addr add 10.0.2.10/24 dev eth0
sudo ip route add default via 10.0.2.1
```

Test :

```bash
ping -c3 10.0.2.10
```

✅ Réponses = tout le réseau OVN fonctionne avec de vraies VMs réelles.

---

# 🔒 Étape 7 — (Option) DHCP, ACL, NAT

Tu peux réutiliser exactement les commandes de ton **Atelier 2** :

* DHCP OVN pour attribuer les IP automatiquement
* ACL pour filtrer le trafic
* NAT pour faire sortir tes VMs vers Internet via `br-ex`

Exemple (control) :

```bash
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.1.0/24
```

---

# ✅ **Résumé global**

| Élément                 | Rôle                                                |
| ----------------------- | --------------------------------------------------- |
| `control`               | Cerveau OVN : gère le réseau logique (northd + DBs) |
| `compute1` / `compute2` | Hôtes physiques (data plane)                        |
| `br-int`                | Switch virtuel interne géré par OVN                 |
| `vnet0`                 | Interface libvirt connectée à la VM réelle          |
| `ovn-controller`        | Télécharge la config et programme OVS               |
| `vmA` / `vmB`           | Vraies VMs avec OS et applicatifs                   |
| `GENEVE`                | Tunnel overlay entre computes                       |

Tu obtiens :

* Un **réseau virtuel distribué** complet,
* Des **vraies VMs** avec IPs et routes gérées par OVN,
* Un environnement 100 % **sans OpenStack**.

---

Souhaites-tu que je te fournisse 🔧 **un script d’automatisation complet** (provisioning Vagrant + installation OVN + libvirt + création des vraies VMs A/B + rattachement OVN) ?
→ Ainsi tu aurais un **mini-cloud OVN sans OpenStack “tout-en-un”** qui se lance avec un simple `vagrant up`.


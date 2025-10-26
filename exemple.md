Oui — c’est tout à fait possible de faire un lab **OVN/OVS + OpenFlow** avec **VirtualBox + Vagrant**.
Voici l’essentiel + un mini-lab prêt à lancer.

---

# Ce qu’il faut savoir (très bref)

* **Sur PC/serveur x86_64 (Windows/Linux/mac Intel)** : VirtualBox + Vagrant fonctionnent très bien pour OVN/OVS.

* **Sur Mac Apple Silicon (M1/M2/M3)** : VirtualBox est limité. Ça peut marcher avec des VM ARM mais les paquets OVS/OVN précompilés sont moins simples. Alternatives plus confortables : UTM/QRUEMU, Colima+QEMU, Multipass, ou un hôte Linux avec libvirt.
  *Si vous êtes sur Mac Intel → go VirtualBox ; sur Apple Silicon → préférez QEMU/UTM.*

* Réseau : prévoyez **une carte “host-only”** (overlay GENEVE entre VMs) + NAT (apt update). MTU par défaut 1500 suffit, OVN adapte les tunnels.

---

# Mini-Lab Vagrant (3 VMs)

## Topologie logique

* `central` : OVN Central (OVSDB north/south + `ovn-northd`)
* `node1` et `node2` : hyperviseurs OVS/OVN Controller (bridge `br-int`), où l’on branchera des “VM simulées” (ports internes)

Overlay : GENEVE entre `node1` et `node2` via réseau privé 192.168.56.0/24 (host-only VirtualBox).

## Fichier `Vagrantfile`

Copiez ces fichiers dans un dossier vide puis `vagrant up` :

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.provider "virtualbox" do |vb|
    vb.cpus = 2
    vb.memory = 2048
  end

  # Réseau commun (host-only) pour le contrôleur OVN et les nodes
  # Adaptez le nom du réseau host-only si besoin.
  def net(vm, ip)
    vm.vm.network "private_network", ip: ip
  end

  # Provision commun (OVS/OVN)
  config.vm.provision "file", source: "install_common.sh", destination: "/tmp/install_common.sh"
  config.vm.provision "shell", inline: "chmod +x /tmp/install_common.sh"

  # ---------- central ----------
  config.vm.define "central" do |c|
    c.vm.hostname = "central"
    net(c, "192.168.56.10")
    c.vm.provision "file", source: "setup_ovn_central.sh", destination: "/tmp/setup_ovn_central.sh"
    c.vm.provision "shell", inline: <<-SHELL
      /tmp/install_common.sh
      bash /tmp/setup_ovn_central.sh 192.168.56.10
    SHELL
  end

  # ---------- node1 ----------
  config.vm.define "node1" do |n1|
    n1.vm.hostname = "node1"
    net(n1, "192.168.56.11")
    n1.vm.provision "file", source: "setup_node.sh", destination: "/tmp/setup_node.sh"
    n1.vm.provision "shell", inline: <<-SHELL
      /tmp/install_common.sh
      bash /tmp/setup_node.sh 192.168.56.10 192.168.56.11
    SHELL
  end

  # ---------- node2 ----------
  config.vm.define "node2" do |n2|
    n2.vm.hostname = "node2"
    net(n2, "192.168.56.12")
    n2.vm.provision "file", source: "setup_node.sh", destination: "/tmp/setup_node.sh"
    n2.vm.provision "shell", inline: <<-SHELL
      /tmp/install_common.sh
      bash /tmp/setup_node.sh 192.168.56.10 192.168.56.12
    SHELL
  end
end
```

## Script `install_common.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openvswitch-switch ovn-central ovn-host jq iproute2

# Activer OVS au boot
systemctl enable openvswitch-switch
systemctl start openvswitch-switch
```

## Script `setup_ovn_central.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
CENTRAL_IP="${1:-192.168.56.10}"

# Activer services OVN Central
systemctl enable ovn-central
systemctl start ovn-central

# Dire à OVN où sont les DB (sur central)
ovs-vsctl set open . external-ids:ovn-remote="tcp:${CENTRAL_IP}:6642" \
                     external-ids:ovn-remote-probe-interval=1000 \
                     external-ids:ovn-openflow-probe-interval=10 \
                     external-ids:ovn-encap-type=geneve \
                     external-ids:ovn-encap-ip="${CENTRAL_IP}"

# Lancer northd (traduit la NB DB vers SB DB / OpenFlow)
systemctl enable ovn-northd
systemctl start ovn-northd

echo "[INFO] OVN Central prêt sur ${CENTRAL_IP}"
```

## Script `setup_node.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
CENTRAL_IP="${1:-192.168.56.10}"
NODE_IP="${2:-192.168.56.11}"

# Démarrer le démon ovn-controller
systemctl enable ovn-host
systemctl start ovn-host

# Intégration OVS (br-int) si absent
ovs-vsctl --may-exist add-br br-int
ovs-vsctl set bridge br-int protocols=OpenFlow13,OpenFlow15 fail-mode=secure
ovs-vsctl set open . external-ids:ovn-remote="tcp:${CENTRAL_IP}:6642" \
                     external-ids:ovn-openflow-probe-interval=10 \
                     external-ids:ovn-encap-ip="${NODE_IP}" \
                     external-ids:ovn-encap-type=geneve

systemctl restart ovn-controller || true

echo "[INFO] Node prêt. Central=${CENTRAL_IP}, NodeIP=${NODE_IP}"
```

---

# Créer une topologie OVN en 2 minutes

Sur la VM **central** (`vagrant ssh central`) :

```bash
# 1) Deux switches logiques + un routeur logique
ovn-nbctl ls-add ls-A
ovn-nbctl ls-add ls-B
ovn-nbctl lr-add lr-AB

# 2) Connecter ls-A et ls-B au routeur
ovn-nbctl lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
ovn-nbctl lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
ovn-nbctl lsp-add ls-A lsp-A-lr
ovn-nbctl lsp-set-type lsp-A-lr router
ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

ovn-nbctl lsp-add ls-B lsp-B-lr
ovn-nbctl lsp-set-type lsp-B-lr router
ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# 3) Créer 2 ports logiques "VM" (un sur chaque switch)
ovn-nbctl lsp-add ls-A vmA
ovn-nbctl lsp-set-addresses vmA "50:54:00:00:00:0a 10.0.1.10"
ovn-nbctl lsp-add ls-B vmB
ovn-nbctl lsp-set-addresses vmB "50:54:00:00:00:0b 10.0.2.10"

# 4) Affichage état
ovn-nbctl show
```

---

# “Brancher” des hôtes de test sur node1/node2

Sur **node1** (`vagrant ssh node1`) :

```bash
# Port interne comme "VM"
ovs-vsctl --may-exist add-port br-int vmA-int -- set Interface vmA-int type=internal external-ids:iface-id=vmA
ip link set vmA-int up
ip addr add 10.0.1.10/24 dev vmA-int
ip route add default via 10.0.1.1 metric 100 || true
```

Sur **node2** (`vagrant ssh node2`) :

```bash
ovs-vsctl --may-exist add-port br-int vmB-int -- set Interface vmB-int type=internal external-ids:iface-id=vmB
ip link set vmB-int up
ip addr add 10.0.2.10/24 dev vmB-int
ip route add default via 10.0.2.1 metric 100 || true
```

**Test :**

* Depuis `node1` : `ping -c3 10.0.2.10`
  (trafic traverse OVN via tunnel GENEVE → routage logique → OK)

---

# Observer les flux OpenFlow (liés à OVN)

Sur n’importe quel node :

```bash
# Flows injectés par OVN dans br-int
ovs-ofctl -O OpenFlow13 dump-flows br-int

# Tracer une décision datapath (équivalent simulateur)
ovs-appctl ofproto/trace br-int "in_port=LOCAL,dl_type=0x0800,nw_src=10.0.1.10,nw_dst=10.0.2.10"
```

Sur `central` :

```bash
# Côté OVN
ovn-sbctl lflow-list | head -n 50
ovn-nbctl list logical_switch_port
ovn-sbctl show
```

---

# Pièges et conseils

* **MTU** : OVN règle les tunnels, mais si vous ajoutez des veth/namespaces, fixez `mtu 1442` si vous voyez du “fragmentation needed”.
* **Pare-feu invité** : désactivez `ufw` si vous avez des surprises.
* **MAC Apple Silicon** : préférez UTM/Colima (QEMU). Le lab ci-dessus reste valide mais changez de provider.

---

## Conclusion

* **Oui, c’est possible** avec VirtualBox + Vagrant.
* Le Vagrantfile + scripts ci-dessus vous donnent un **lab minimal reproductible** pour :

  * Créer une **topologie OVN** (switches/routeur logiques).
  * **Attacher des “VM” simulées** (ports internes OVS) sur 2 nœuds.
  * **Observer les règles OpenFlow** générées automatiquement par OVN.

Si vous voulez, je peux vous fournir une variante **Apple Silicon/QEMU** ou enrichir le lab (NAT nord/sud, ACL/Firewall, DNAT/SNAT, DHCP OVN, Load-Balancers, TRACEs détaillés).

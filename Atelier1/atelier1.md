Parfait 👌
On va créer **un vrai lab OVN/OVS complet** avec **VirtualBox + Vagrant** basé sur ton **Atelier 1 – Installation et configuration** :

> 🎯 Objectif :
> 1 VM **control** (OVN Central) + 2 VMs **compute** (OVS/OVN Controller).
> Configuration de `br-int`, `br-ex`, `br-local`, et lancement manuel/automatique de :
> `ovn-northd`, `ovsdb-server`, `ovn-controller`.

---

## 🧩 Structure du lab

| Nom VM   | Rôle         | IP Privée (Host-only) | Services principaux   |
| -------- | ------------ | --------------------- | --------------------- |
| control  | OVN Central  | 192.168.56.10         | ovn-northd, NB/SB DBs |
| compute1 | Node OVN/OVS | 192.168.56.11         | ovn-controller, ovs   |
| compute2 | Node OVN/OVS | 192.168.56.12         | ovn-controller, ovs   |

---

## 📁 Arborescence

```
ovn-lab/
├── Vagrantfile
├── scripts/
│   ├── install_common.sh
│   ├── setup_control.sh
│   └── setup_compute.sh
```

---

## 🧱 Fichier `Vagrantfile`

```ruby
Vagrant.configure("2") do |config|
    config.vm.box = "ubuntu/jammy64"
  
    # ====== Provider VirtualBox (appliqué à TOUTES les VMs) ======
    config.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
  
      # Carte 1 = NAT (pour apt update, etc.)
      vb.customize ["modifyvm", :id, "--nic1", "nat"]
  
      # Carte 2 = Host-Only et on force le NOM exact de l'adaptateur
      vb.customize ["modifyvm", :id, "--nic2", "hostonly"]
      vb.customize ["modifyvm", :id, "--hostonlyadapter2", "VirtualBox Host-Only Ethernet Adapter #2"]
      # Si dans ta GUI il s'appelle "#2", mets exactement :
      # vb.customize ["modifyvm", :id, "--hostonlyadapter2", "VirtualBox Host-Only Ethernet Adapter #2"]
    end
  
    # Petit helper pour attribuer l'IP sur la NIC2 (host-only)
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
        chmod +x /tmp/install_common.sh /tmp/setup_compute.sh
        bash /tmp/install_common.sh
        bash /tmp/setup_compute.sh 192.168.56.10 192.168.56.12
      SHELL
    end
  end
```

---

## ⚙️ Script `scripts/install_common.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Installation des paquets communs..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openvswitch-switch ovn-common ovn-host ovn-central tcpdump net-tools iproute2

systemctl enable openvswitch-switch
systemctl start openvswitch-switch

# Vérification
ovs-vsctl show
```

---

## 🧭 Script `scripts/setup_control.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Configuration du noeud control (northd + DB)..."

# Activer les services OVN Central
systemctl enable ovn-central
systemctl start ovn-central

# Lancer ovn-northd
systemctl enable ovn-northd
systemctl start ovn-northd

# Configurer les bridges
ovs-vsctl --may-exist add-br br-int
ovs-vsctl --may-exist add-br br-ex
ovs-vsctl --may-exist add-br br-local

# Vérification
ovs-vsctl show

echo "[INFO] Control node prêt."
```

---

## 🧭 Script `scripts/setup_compute.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

CENTRAL_IP="${1:-192.168.56.10}"
NODE_IP="${2:-192.168.56.11}"

echo "[INFO] Configuration du noeud compute avec Central=${CENTRAL_IP}"

# Créer les bridges
ovs-vsctl --may-exist add-br br-int
ovs-vsctl --may-exist add-br br-ex
ovs-vsctl --may-exist add-br br-local

# Configurer l'intégration OVN
ovs-vsctl set open . \
  external-ids:ovn-remote="tcp:${CENTRAL_IP}:6642" \
  external-ids:ovn-openflow-probe-interval=10 \
  external-ids:ovn-encap-ip="${NODE_IP}" \
  external-ids:ovn-encap-type=geneve

# Démarrer ovn-controller
systemctl enable ovn-controller
systemctl start ovn-controller

# Vérification
ovs-vsctl show
systemctl status ovn-controller --no-pager

echo "[INFO] Compute node prêt : ${NODE_IP}"
```

---
Excellent 👍 Voici ton **Atelier 1** réajusté avec uniquement les **commandes utiles, testables et pertinentes** juste après ton `vagrant up`, sans rien d’inutile ou prématuré.
Tout est vérifiable et cohérent avec la configuration que tu as mise en place 👇

---

Une fois le lab monté :

```bash
vagrant ssh control
vagrant ssh compute1
vagrant ssh compute2
```

---

## 🧪 Vérifications de base

### 🖥️ Sur `control`

```bash
# Vérifier que le démon de contrôle OVN est actif
sudo systemctl status ovn-northd --no-pager

# Vérifier la présence des bases de données NB et SB
sudo ss -ltnp | grep 664  # doit afficher les ports 6641 (NB) et 6642 (SB)

# Voir si les nœuds compute sont enregistrés (tunnels GENEVE)
sudo ovn-sbctl show
```

✅ Tu dois voir apparaître deux chassis (compute1 et compute2) avec leur IP GENEVE :

```
Chassis "UUID..."
    hostname: compute1
    Encap geneve
        ip: "192.168.56.11"
Chassis "UUID..."
    hostname: compute2
    Encap geneve
        ip: "192.168.56.12"
```

---

### 🖧 Sur `compute1` et `compute2`

```bash
# Vérifier la configuration OVN côté compute
sudo ovs-vsctl get open . external-ids:ovn-remote

# Vérifier les bridges et interfaces créés (br-int, br-ex, br-local)
sudo ovs-vsctl show

# Vérifier que le contrôleur OVN local est actif et connecté
sudo systemctl status ovn-controller --no-pager
```

✅ Tu dois voir :

* Les bridges `br-int`, `br-ex`, `br-local` listés.
* L’état du service `ovn-controller` = **active (running)**.
* La ligne `external-ids:ovn-remote="tcp:192.168.56.10:6642"` (le lien vers le control).

---

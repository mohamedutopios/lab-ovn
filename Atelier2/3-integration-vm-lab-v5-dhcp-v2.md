Parfait ! Voici le guide complet pour passer de votre lab avec IPs statiques vers DHCP :

---

## Lab : Transition IP Statique → DHCP

### Étape 1 : Supprimer les VMs existantes

**Sur compute1 :**
```bash
vagrant ssh compute1
```

```bash
# Supprimer vmA
sudo virsh destroy vmA 2>/dev/null || true
sudo virsh undefine vmA 2>/dev/null || true
sudo rm -f /var/lib/libvirt/images/vmA*
sudo rm -f /var/lib/libvirt/images/user-data-vmA
sudo rm -f /var/lib/libvirt/images/meta-data-vmA

exit
```

**Sur compute2 :**
```bash
vagrant ssh compute2
```

```bash
# Supprimer vmB
sudo virsh destroy vmB 2>/dev/null || true
sudo virsh undefine vmB 2>/dev/null || true
sudo rm -f /var/lib/libvirt/images/vmB*
sudo rm -f /var/lib/libvirt/images/user-data-vmB
sudo rm -f /var/lib/libvirt/images/meta-data-vmB

exit
```

### Étape 2 : Reconfigurer OVN pour DHCP (sur control)

```bash
vagrant ssh control
```

```bash
# Supprimer les anciens ports logiques
sudo ovn-nbctl lsp-del vmA 2>/dev/null || true
sudo ovn-nbctl lsp-del vmB 2>/dev/null || true

# Recréer les ports logiques
sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-add ls-B vmB

# === CONFIGURATION DHCP ===

# Créer les pools DHCP pour chaque réseau
UUID_A=$(sudo ovn-nbctl create DHCP_Options \
  cidr="10.0.1.0/24" \
  options='{"server_id"="10.0.1.1", "server_mac"="02:aa:aa:aa:aa:01", "lease_time"="3600", "router"="10.0.1.1", "dns_server"="8.8.8.8"}')

UUID_B=$(sudo ovn-nbctl create DHCP_Options \
  cidr="10.0.2.0/24" \
  options='{"server_id"="10.0.2.1", "server_mac"="02:bb:bb:bb:bb:01", "lease_time"="3600", "router"="10.0.2.1", "dns_server"="8.8.8.8"}')

echo "UUID_A créé: $UUID_A"
echo "UUID_B créé: $UUID_B"

# Configurer les ports en mode DHCP dynamique
sudo ovn-nbctl lsp-set-addresses vmA "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmA "$UUID_A"
sudo ovn-nbctl clear logical_switch_port vmA port_security
sudo ovn-nbctl lsp-set-port-security vmA "52:54:00:aa:00:10"

sudo ovn-nbctl lsp-set-addresses vmB "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmB "$UUID_B"
sudo ovn-nbctl clear logical_switch_port vmB port_security
sudo ovn-nbctl lsp-set-port-security vmB "52:54:00:bb:00:10"

# Synchroniser avec les hypervisors
sudo ovn-nbctl --wait=hv sync

# Vérifier la configuration DHCP
echo ""
echo "=== Configuration DHCP vmA ==="
sudo ovn-nbctl get logical_switch_port vmA addresses
sudo ovn-nbctl get logical_switch_port vmA dhcpv4_options

echo ""
echo "=== Configuration DHCP vmB ==="
sudo ovn-nbctl get logical_switch_port vmB addresses
sudo ovn-nbctl get logical_switch_port vmB dhcpv4_options

echo ""
echo "=== Topologie complète ==="
sudo ovn-nbctl show

exit
```

### Étape 3 : Recréer vmA avec DHCP (sur compute1)

```bash
vagrant ssh compute1
```

```bash
cd /var/lib/libvirt/images

# Télécharger l'image si pas déjà fait
if [ ! -f jammy.img ]; then
    sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
    sudo qemu-img resize jammy.img 10G
fi

# Créer l'image pour vmA
sudo cp jammy.img vmA.img

# Cloud-init SANS configuration réseau statique (DHCP automatique)
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

# Créer la VM
sudo virt-install \
  --name vmA \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmA.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmA-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:aa:00:10 \
  --import --graphics none


sudo virsh domiflist vmA    # récupère le Target, ex: vnet3
IF=vnet3
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmA \
  external-ids:attached-mac=52:54:00:aa:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport   # >0 (pas -1)

### Étape 4 : Recréer vmB avec DHCP (sur compute2)
```bash
vagrant ssh compute2
```

```bash
cd /var/lib/libvirt/images

# Télécharger l'image si pas déjà fait
if [ ! -f jammy.img ]; then
    sudo wget -O jammy.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
    sudo qemu-img resize jammy.img 10G
fi

# Créer l'image pour vmB
sudo cp jammy.img vmB.img

# Cloud-init SANS configuration réseau statique (DHCP automatique)
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

# Créer la VM
sudo virt-install \
  --name vmB \
  --ram 1024 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/vmB.img,format=qcow2,bus=virtio \
  --disk path=/var/lib/libvirt/images/vmB-seed.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=ovn,model=virtio,mac=52:54:00:bb:00:10 \
  --import --graphics none


sudo virsh domiflist vmB    # ex: vnet4
IF=vnet4
sudo ovs-vsctl set Interface $IF external-ids:iface-id=vmB \
  external-ids:attached-mac=52:54:00:bb:00:10 \
  external-ids:iface-status=active
sudo ovs-vsctl list-ports br-int | grep $IF
sudo ovs-vsctl get Interface $IF ofport

### Étape 5 : Vérifications (sur control)

```bash
echo "=== Vérification des Chassis ==="
sudo ovn-sbctl list Chassis | egrep 'hostname|name|^$'

echo ""
echo "=== Vérification des Port Bindings ==="
sudo ovn-sbctl --format=table --columns=logical_port,chassis,up list Port_Binding | egrep 'vmA|vmB|logical_port|chassis|up'

echo ""
echo "=== Configuration DHCP vmA ==="
sudo ovn-nbctl get logical_switch_port vmA addresses
sudo ovn-nbctl get logical_switch_port vmA dhcpv4_options

echo ""
echo "=== Configuration DHCP vmB ==="
sudo ovn-nbctl get logical_switch_port vmB addresses
sudo ovn-nbctl get logical_switch_port vmB dhcpv4_options

exit
```

### Étape 6 : Tester DHCP dans les VMs

**Tester vmA :**
```bash
vagrant ssh compute1
sudo virsh console vmA
```

Dans la console de vmA (login: ubuntu / ubuntu) :
```bash
# Activer l'interface et obtenir une IP via DHCP
sudo ip link set enp1s0 up
sudo dhclient -v enp1s0

# Vérifier l'IP obtenue (devrait être dans 10.0.1.0/24)
ip -4 a show enp1s0
ip route

# Noter l'IP obtenue pour le test de ping
```

Quitter la console : `Ctrl + ]`

**Tester vmB :**
```bash
# Depuis votre machine hôte
vagrant ssh compute2
sudo virsh console vmB
```

Dans la console de vmB (login: ubuntu / ubuntu) :
```bash
# Activer l'interface et obtenir une IP via DHCP
sudo ip link set enp1s0 up
sudo dhclient -v enp1s0

# Vérifier l'IP obtenue (devrait être dans 10.0.2.0/24)
ip -4 a show enp1s0
ip route

# Tester le ping vers vmA (utiliser l'IP notée précédemment)
# Par exemple si vmA a obtenu 10.0.1.10 :
ping -c3 10.0.1.10
```

### Étape 7 : Test croisé de connectivité

Dans vmA, pinger vmB :
```bash
# Si vmB a obtenu par exemple 10.0.2.15
ping -c3 10.0.2.15
```

---

## Résumé de la transition

**Ce qui a changé :**

| Aspect | IP Statique | DHCP |
|--------|-------------|------|
| **Configuration OVN** | `lsp-set-addresses vmA "52:54:00:aa:00:10 10.0.1.10"` | `lsp-set-addresses vmA "dynamic"` + DHCP_Options |
| **Port Security** | MAC + IP fixe | MAC seule |
| **Cloud-init** | Netplan avec IP statique | Pas de configuration réseau (DHCP par défaut) |
| **Dans la VM** | IP configurée au boot | `dhclient` pour obtenir l'IP |
| **IPs allouées** | Prédéfinies (10.0.1.10, 10.0.2.10) | Dynamiques (10.0.1.X, 10.0.2.X) |

**Avantages du DHCP :**
- ✅ Plus flexible pour ajouter/supprimer des VMs
- ✅ Pas besoin de gérer manuellement les IPs
- ✅ OVN gère automatiquement l'allocation

Votre lab est maintenant en mode DHCP ! 🎉
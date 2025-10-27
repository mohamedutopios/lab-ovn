Parfait ! Voici comment ajouter le NAT source/destination à votre lab OVN existant avec IPs fixes.

---

## Lab : Ajout du NAT Source/Destination

### Architecture cible

```
Internet/Host (192.168.56.0/24)
         |
    [br-ex] (192.168.56.100) ← IP externe du routeur
         |
      lr-AB (Logical Router avec NAT)
       /   \
   ls-A   ls-B
    |       |
  vmA     vmB
(10.0.1.10) (10.0.2.10)
```

**Fonctionnalités NAT :**
- **SNAT** : vmA et vmB peuvent accéder à Internet via 192.168.56.100
- **DNAT** : Port forwarding pour exposer des services (ex: SSH sur vmA)

---

## Étapes manuelles (après avoir votre lab avec IPs fixes)

### Étape 1 : Sur control - Ajouter une interface externe au routeur

```bash
vagrant ssh control
```

```bash
# Créer un nouveau Logical Switch pour l'externe
sudo ovn-nbctl --may-exist ls-add ls-external

# Ajouter un port routeur externe sur lr-AB
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-external 02:ee:ee:ee:ee:01 192.168.56.100/24

# Connecter le switch externe au routeur
sudo ovn-nbctl --may-exist lsp-add ls-external lsp-external-lr
sudo ovn-nbctl lsp-set-type lsp-external-lr router
sudo ovn-nbctl lsp-set-addresses lsp-external-lr "02:ee:ee:ee:ee:01"
sudo ovn-nbctl lsp-set-options lsp-external-lr router-port=lrp-external

# Définir le routeur comme gateway
sudo ovn-nbctl set logical_router lr-AB options:chassis=compute1

# Vérifier
sudo ovn-nbctl show

exit
```

### Étape 2 : Sur compute1 - Créer le bridge externe br-ex

```bash
vagrant ssh compute1
```

```bash
# Créer le bridge externe
sudo ovs-vsctl --may-exist add-br br-ex

# Activer le bridge
sudo ip link set br-ex up

# Ajouter une IP au bridge (gateway externe)
sudo ip addr add 192.168.56.100/24 dev br-ex

# Ajouter une route par défaut si nécessaire
sudo ip route add default via 192.168.56.1 dev br-ex 2>/dev/null || true

# Vérifier
ip addr show br-ex
ip route

exit
```

### Étape 3 : Sur control - Créer un port locnet pour connecter ls-external à br-ex

```bash
vagrant ssh control
```

```bash
# Créer un port de type localnet qui mappe ls-external vers br-ex
sudo ovn-nbctl --may-exist lsp-add ls-external lsp-localnet-external
sudo ovn-nbctl lsp-set-type lsp-localnet-external localnet
sudo ovn-nbctl lsp-set-addresses lsp-localnet-external unknown
sudo ovn-nbctl lsp-set-options lsp-localnet-external network_name=external

# Vérifier
sudo ovn-nbctl show

exit
```

### Étape 4 : Sur compute1 - Mapper le réseau externe au bridge

```bash
vagrant ssh compute1
```

```bash
# Configurer le mapping entre le réseau OVN "external" et br-ex
sudo ovs-vsctl set open_vswitch . \
  external-ids:ovn-bridge-mappings="external:br-ex"

# Redémarrer ovn-controller pour appliquer
sudo systemctl restart ovn-controller

# Vérifier
sudo ovs-vsctl get open_vswitch . external-ids:ovn-bridge-mappings

# Vérifier que br-ex a des flows
sudo ovs-ofctl dump-flows br-ex

exit
```

### Étape 5 : Sur control - Configurer le SNAT (Source NAT)

```bash
vagrant ssh control
```

```bash
# SNAT pour ls-A (10.0.1.0/24 → 192.168.56.100)
sudo ovn-nbctl --may-exist lr-nat-add lr-AB snat 192.168.56.100 10.0.1.0/24

# SNAT pour ls-B (10.0.2.0/24 → 192.168.56.100)
sudo ovn-nbctl --may-exist lr-nat-add lr-AB snat 192.168.56.100 10.0.2.0/24

# Vérifier les règles NAT
echo "=== Règles NAT sur lr-AB ==="
sudo ovn-nbctl lr-nat-list lr-AB

# Ajouter une route par défaut sur le routeur logique
sudo ovn-nbctl lr-route-add lr-AB 0.0.0.0/0 192.168.56.1

# Vérifier les routes
echo "=== Routes sur lr-AB ==="
sudo ovn-nbctl lr-route-list lr-AB

exit
```

### Étape 6 : Tester le SNAT depuis vmA

```bash
vagrant ssh compute1
sudo virsh console vmA
```

Dans vmA (login: ubuntu / ubuntu) :
```bash
# Vérifier la configuration réseau
ip addr show enp1s0
ip route

# Tester la connectivité vers la gateway
ping -c3 10.0.1.1

# Tester la connectivité vers l'IP externe du routeur
ping -c3 192.168.56.100

# Tester la connectivité vers le réseau host-only
ping -c3 192.168.56.1

# Tester la connectivité vers Internet (si disponible)
ping -c3 8.8.8.8

# Vérifier le DNS
cat /etc/resolv.conf
```

Quitter : `Ctrl + ]`

### Étape 7 : Sur control - Configurer le DNAT (Destination NAT / Port Forwarding)

```bash
vagrant ssh control
```

```bash
# Exemple 1: Forwarder le port 2222 externe vers le port 22 de vmA (SSH)
sudo ovn-nbctl --may-exist lr-nat-add lr-AB dnat_and_snat 192.168.56.100:2222 10.0.1.10:22

# Exemple 2: Forwarder le port 8080 externe vers le port 80 de vmB (HTTP)
sudo ovn-nbctl --may-exist lr-nat-add lr-AB dnat_and_snat 192.168.56.100:8080 10.0.2.10:80

# Vérifier toutes les règles NAT
echo "=== Toutes les règles NAT ==="
sudo ovn-nbctl lr-nat-list lr-AB

exit
```

### Étape 8 : Tester le DNAT (Port Forwarding)

**Installer un serveur web sur vmB pour le test :**

```bash
vagrant ssh compute2
sudo virsh console vmB
```

Dans vmB :
```bash
# Installer un serveur web simple
sudo apt update
sudo apt install -y python3

# Lancer un serveur web sur le port 80
sudo python3 -m http.server 80 &

# Vérifier qu'il écoute
sudo ss -tlnp | grep :80
```

Quitter : `Ctrl + ]`

**Tester depuis votre machine hôte Windows :**

```powershell
# Tester l'accès HTTP via DNAT
curl http://192.168.56.100:8080
# ou ouvrir dans un navigateur : http://192.168.56.100:8080
```

**Tester le SSH forwarding vers vmA depuis compute1 :**

```bash
vagrant ssh compute1
```

```bash
# Tester SSH via DNAT (depuis compute1 vers vmA via IP externe)
ssh -p 2222 ubuntu@192.168.56.100
# Mot de passe: ubuntu
```

---

## Vérifications complètes

### Sur control - État complet du NAT

```bash
vagrant ssh control
```

```bash
echo "=== Topologie OVN complète ==="
sudo ovn-nbctl show

echo ""
echo "=== Routes sur lr-AB ==="
sudo ovn-nbctl lr-route-list lr-AB

echo ""
echo "=== Règles NAT sur lr-AB ==="
sudo ovn-nbctl lr-nat-list lr-AB

echo ""
echo "=== Options du routeur ==="
sudo ovn-nbctl get logical_router lr-AB options

exit
```

### Sur compute1 - Vérifier br-ex et les flows

```bash
vagrant ssh compute1
```

```bash
echo "=== Configuration br-ex ==="
sudo ovs-vsctl show | grep -A10 br-ex

echo ""
echo "=== IP de br-ex ==="
ip addr show br-ex

echo ""
echo "=== Flows sur br-ex ==="
sudo ovs-ofctl dump-flows br-ex | head -20

echo ""
echo "=== Bridge mappings ==="
sudo ovs-vsctl get open_vswitch . external-ids:ovn-bridge-mappings

echo ""
echo "=== Routes ==="
ip route

exit
```

---

## Résumé de la configuration NAT

### SNAT (Source NAT) - Sortie vers Internet
- **10.0.1.0/24** (ls-A) → **192.168.56.100** (IP externe)
- **10.0.2.0/24** (ls-B) → **192.168.56.100** (IP externe)
- Les VMs peuvent accéder au réseau host-only et Internet

### DNAT (Destination NAT) - Port Forwarding
- **192.168.56.100:2222** → **10.0.1.10:22** (SSH vers vmA)
- **192.168.56.100:8080** → **10.0.2.10:80** (HTTP vers vmB)

### Architecture finale

```
                    Internet
                       |
          192.168.56.1 (Host)
                       |
    ┌──────────────────┴──────────────────┐
    │         192.168.56.0/24             │
    │  (Réseau Host-Only VirtualBox)      │
    └──────────────────┬──────────────────┘
                       |
              192.168.56.100 (br-ex sur compute1)
                       |
                   [ls-external]
                       |
                    [lr-AB] ← Routeur avec NAT
                   /   |   \
                  /    |    \
          [ls-A]      [ls-B]
             |          |
         10.0.1.10  10.0.2.10
          (vmA)      (vmB)
```

---

## Commandes utiles pour gérer le NAT

### Lister les règles NAT
```bash
sudo ovn-nbctl lr-nat-list lr-AB
```

### Supprimer une règle SNAT
```bash
sudo ovn-nbctl lr-nat-del lr-AB snat 192.168.56.100 10.0.1.0/24
```

### Supprimer une règle DNAT
```bash
sudo ovn-nbctl lr-nat-del lr-AB dnat_and_snat 192.168.56.100:2222
```

### Ajouter une nouvelle règle DNAT
```bash
sudo ovn-nbctl lr-nat-add lr-AB dnat_and_snat <IP_EXTERNE:PORT> <IP_INTERNE:PORT>
```

Votre lab OVN dispose maintenant d'un NAT complet avec connectivité externe ! 🎉🌐
Excellente idée ! Recommençons proprement sur compute2 avec vmB. Voici un guide pas à pas simple et clair.

---

# Démo SNAT sur compute2 - Accès Internet pour vmB

## Architecture
```
Internet (via enp0s3)
         ↓
   [compute2] NAT Linux
         ↓
  192.168.56.200 (IP publique)
         ↓
     [lr-AB] OVN SNAT
         ↓
      ls-B
         ↓
       vmB
    10.0.2.10
```

---

## Étape 1 : Diagnostic de base sur compute2

```bash
vagrant ssh compute2
```

```bash
# Vérifier les interfaces
echo "=== Interfaces ==="
ip -br addr

# Vérifier les routes
echo ""
echo "=== Routes ==="
ip route show

# Tester la connectivité Internet depuis compute2
echo ""
echo "=== Test Internet depuis compute2 ==="
ping -c3 8.8.8.8

# Si le ping fonctionne, on peut continuer
```

---

## Étape 2 : Activer l'IP forwarding sur compute2

```bash
# Activer l'IP forwarding (requis pour router le trafic)
sudo sysctl -w net.ipv4.ip_forward=1

# Rendre permanent
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ovn.conf

# Vérifier
sysctl net.ipv4.ip_forward
```

---

## Étape 3 : Créer et configurer br-ex sur compute2

```bash
# Créer le bridge externe si pas déjà fait
sudo ovs-vsctl --may-exist add-br br-ex

# Lui donner une IP "publique" (192.168.56.200 pour compute2)
sudo ip addr add 192.168.56.200/24 dev br-ex 2>/dev/null || echo "IP déjà présente"

# Activer le bridge
sudo ip link set br-ex up

# Vérifier
echo ""
echo "=== Configuration br-ex ==="
ip addr show br-ex
```

---

## Étape 4 : Configurer le NAT Linux sur compute2

```bash
# Installer iptables-persistent pour sauvegarder les règles
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# Nettoyer les règles existantes
sudo iptables -t nat -F
sudo iptables -F FORWARD

# Configurer le MASQUERADE sur enp0s3 (interface NAT)
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE

# Autoriser le forwarding
sudo iptables -P FORWARD ACCEPT
sudo iptables -A FORWARD -i br-ex -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o br-ex -j ACCEPT
sudo iptables -A FORWARD -i br-int -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o br-int -j ACCEPT

# Sauvegarder les règles
sudo netfilter-persistent save

# Vérifier la configuration
echo ""
echo "=== Règles NAT ==="
sudo iptables -t nat -L POSTROUTING -n -v

echo ""
echo "=== Règles FORWARD ==="
sudo iptables -L FORWARD -n -v

exit
```

---

## Étape 5 : Configurer le mapping OVN sur compute2

```bash
vagrant ssh compute2
```

```bash
# Configurer le mapping entre le réseau OVN "external" et br-ex
sudo ovs-vsctl set open_vswitch . \
  external-ids:ovn-bridge-mappings="external:br-ex"

# Redémarrer ovn-controller pour appliquer
sudo systemctl restart ovn-controller

# Attendre quelques secondes
sleep 3

# Vérifier
echo "=== Bridge mappings ==="
sudo ovs-vsctl get open_vswitch . external-ids:ovn-bridge-mappings

echo ""
echo "=== OVS bridges ==="
sudo ovs-vsctl show

exit
```

---

## Étape 6 : Configurer OVN sur control

```bash
vagrant ssh control
```

```bash
# Créer le switch externe (si pas déjà fait)
sudo ovn-nbctl --may-exist ls-add ls-external

# Ajouter un port routeur externe sur lr-AB
sudo ovn-nbctl --may-exist lrp-add lr-AB lrp-external 02:ee:ee:ee:ee:02 192.168.56.200/24

# Connecter le switch externe au routeur
sudo ovn-nbctl --may-exist lsp-add ls-external lsp-external-lr
sudo ovn-nbctl lsp-set-type lsp-external-lr router
sudo ovn-nbctl lsp-set-addresses lsp-external-lr "02:ee:ee:ee:ee:02"
sudo ovn-nbctl lsp-set-options lsp-external-lr router-port=lrp-external

# Créer un port localnet pour connecter au bridge physique
sudo ovn-nbctl --may-exist lsp-add ls-external lsp-localnet-external
sudo ovn-nbctl lsp-set-type lsp-localnet-external localnet
sudo ovn-nbctl lsp-set-addresses lsp-localnet-external unknown
sudo ovn-nbctl lsp-set-options lsp-localnet-external network_name=external

# Définir compute2 comme gateway chassis pour le routeur
sudo ovn-nbctl set logical_router lr-AB options:chassis=compute2

# Ajouter la route par défaut dans OVN
# Supprimer l'ancienne si elle existe
sudo ovn-nbctl lr-route-del lr-AB 0.0.0.0/0 2>/dev/null || true

# Ajouter la route vers la gateway (br-ex de compute2)
sudo ovn-nbctl lr-route-add lr-AB 0.0.0.0/0 192.168.56.200 lrp-external

# Configurer le SNAT pour le réseau de vmB
sudo ovn-nbctl --may-exist lr-nat-add lr-AB snat 192.168.56.200 10.0.2.0/24

# On peut aussi ajouter pour ls-A même si vmA est sur compute1
sudo ovn-nbctl --may-exist lr-nat-add lr-AB snat 192.168.56.200 10.0.1.0/24

# Vérifier la configuration
echo ""
echo "=== Topologie OVN ==="
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

---

## Étape 7 : Synchroniser et vérifier sur compute2

```bash
vagrant ssh compute2
```

```bash
# Redémarrer ovn-controller pour s'assurer que tout est synchronisé
sudo systemctl restart ovn-controller

# Attendre
sleep 5

# Vérifier les flows OpenFlow sur br-ex
echo "=== Flows sur br-ex ==="
sudo ovs-ofctl dump-flows br-ex | head -20

# Vérifier les ports de br-ex
echo ""
echo "=== Ports de br-ex ==="
sudo ovs-vsctl list-ports br-ex

# Vérifier que br-int a toujours vmB
echo ""
echo "=== Ports de br-int ==="
sudo ovs-vsctl list-ports br-int

exit
```

---

## Étape 8 : Tester depuis vmB

```bash
vagrant ssh compute2
sudo virsh console vmB
```

Dans vmB (login: ubuntu / ubuntu) :

```bash
# Vérifier la configuration réseau de vmB
echo "=== Configuration réseau vmB ==="
ip addr show enp1s0
ip route show

# Tester la gateway locale (routeur OVN)
echo ""
echo "=== Test gateway locale ==="
ping -c3 10.0.2.1

# Tester l'IP externe du routeur
echo ""
echo "=== Test IP externe routeur ==="
ping -c3 192.168.56.200

# Tester Internet
echo ""
echo "=== Test Internet ==="
ping -c5 8.8.8.8

# Si ça fonctionne, tester le DNS
echo ""
echo "=== Test DNS ==="
ping -c3 google.com

# Installer curl et vérifier l'IP publique vue
sudo apt update && sudo apt install -y curl

# Voir quelle IP est vue depuis Internet
curl https://ifconfig.me
# Devrait montrer l'IP publique de compute2
```

---

## Étape 9 : Diagnostics si ça ne fonctionne pas

### Sur compute2 - Capturer le trafic

Ouvrez un deuxième terminal :

```bash
vagrant ssh compute2
```

```bash
# Capturer le trafic sur br-ex
sudo tcpdump -i br-ex -n icmp
```

Puis dans vmB, refaites un ping vers 8.8.8.8.

Vous devriez voir :
- **Paquets sortants** de vmB vers 8.8.8.8 (avec IP source 192.168.56.200 après NAT)
- **Paquets entrants** de 8.8.8.8 vers 192.168.56.200

### Vérifier les flows

```bash
vagrant ssh compute2
```

```bash
# Flows sur br-int
sudo ovs-ofctl dump-flows br-int | grep -E "10.0.2.10|nw_src"

# Flows sur br-ex
sudo ovs-ofctl dump-flows br-ex | grep -E "192.168.56.200|nw_dst"
```

### Vérifier les connexions actives

```bash
vagrant ssh compute2
```

```bash
# Installer conntrack
sudo apt-get install -y conntrack

# Voir les connexions NAT actives
sudo conntrack -L | grep 10.0.2.10

# Statistiques iptables
sudo iptables -t nat -L POSTROUTING -n -v
```

---

## Résumé de la configuration

| Élément | Configuration |
|---------|---------------|
| **compute2 IP forwarding** | ✅ Activé |
| **compute2 br-ex** | 192.168.56.200/24 |
| **compute2 NAT iptables** | MASQUERADE sur enp0s3 |
| **OVN mapping** | external:br-ex |
| **OVN Gateway chassis** | compute2 |
| **OVN Route par défaut** | 0.0.0.0/0 → 192.168.56.200 |
| **OVN SNAT** | 10.0.2.0/24 → 192.168.56.200 |
| **vmB IP** | 10.0.2.10/24 |
| **vmB Gateway** | 10.0.2.1 (routeur OVN) |

---

## Commandes de vérification rapide

```bash
# Sur compute2
vagrant ssh compute2 -c "ping -c1 8.8.8.8 && echo '✓ compute2 → Internet OK'"

# Sur control
vagrant ssh control -c "sudo ovn-nbctl lr-nat-list lr-AB"

# Depuis vmB
vagrant ssh compute2 -c "sudo virsh console vmB"
# Puis dans vmB: ping -c3 8.8.8.8
```

Suivez ces étapes une par une et dites-moi à quelle étape vous rencontrez un problème si jamais ! 🚀
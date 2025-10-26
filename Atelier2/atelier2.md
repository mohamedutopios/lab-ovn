Parfait 👍 voici la version complète, claire et **testable pas à pas** de ton :

# 🧩 **Atelier 2 – Manipulation avec les outils OVN**

---

## 🎯 **Objectif**

Créer manuellement une topologie logique complète dans OVN :

* 2 Logical Switches (`ls-A`, `ls-B`)
* 1 Logical Router (`lr-AB`)
* Ports logiques connectés à des « VM » simulées
* Attribution automatique d’IP (DHCP OVN)
* ACL pour ICMP et HTTP
* NAT (SNAT + DNAT)

---

## ⚙️ **Pré-requis**

Atelier 1 opérationnel ✅
Les deux nœuds `compute1` et `compute2` apparaissent dans :

```bash
sudo ovn-sbctl show
```

---

## 🧱 **1. Commandes principales (rappel)**

| Outil               | Usage                                |
| ------------------- | ------------------------------------ |
| `ovn-nbctl show`    | Voir la configuration logique (NBDB) |
| `ovn-sbctl show`    | Voir les châssis et tunnels (SBDB)   |
| `ovn-nbctl ls-add`  | Créer un Logical Switch              |
| `ovn-nbctl lr-add`  | Créer un Logical Router              |
| `ovn-nbctl lsp-add` | Créer un port sur un Switch          |
| `ovn-nbctl lrp-add` | Créer un port sur un Router          |

---

## 🧩 **2. Création du réseau logique**

Sur **`control`** :

```bash
# 2 switches logiques + 1 routeur
sudo ovn-nbctl ls-add ls-A
sudo ovn-nbctl ls-add ls-B
sudo ovn-nbctl lr-add lr-AB

# Relier ls-A au routeur (10.0.1.0/24)
sudo ovn-nbctl lrp-add lr-AB lrp-AB-A 02:aa:aa:aa:aa:01 10.0.1.1/24
sudo ovn-nbctl lsp-add ls-A lsp-A-lr
sudo ovn-nbctl lsp-set-type lsp-A-lr router
sudo ovn-nbctl lsp-set-addresses lsp-A-lr "02:aa:aa:aa:aa:01"
sudo ovn-nbctl lsp-set-options lsp-A-lr router-port=lrp-AB-A

# Relier ls-B au routeur (10.0.2.0/24)
sudo ovn-nbctl lrp-add lr-AB lrp-AB-B 02:bb:bb:bb:bb:01 10.0.2.1/24
sudo ovn-nbctl lsp-add ls-B lsp-B-lr
sudo ovn-nbctl lsp-set-type lsp-B-lr router
sudo ovn-nbctl lsp-set-addresses lsp-B-lr "02:bb:bb:bb:bb:01"
sudo ovn-nbctl lsp-set-options lsp-B-lr router-port=lrp-AB-B

# Créer 2 ports "VM"
sudo ovn-nbctl lsp-add ls-A vmA
sudo ovn-nbctl lsp-add ls-B vmB

# Vérifier
sudo ovn-nbctl show
```

✅ Tu dois voir : `ls-A`, `ls-B`, `lr-AB`, et leurs ports.

---

## 🧮 **3. Connexion des interfaces simulées**

Sur **compute1** :

```bash
sudo ovs-vsctl --may-exist add-port br-int vmA-int \
  -- set Interface vmA-int type=internal external-ids:iface-id=vmA
sudo ip link set vmA-int up
```

Sur **compute2** :

```bash
sudo ovs-vsctl --may-exist add-port br-int vmB-int \
  -- set Interface vmB-int type=internal external-ids:iface-id=vmB
sudo ip link set vmB-int up
```

---

## 🌐 **4. DHCP OVN (attribution automatique d’adresses)**

Sur **control** :

```bash
# DHCP pour ls-A
UUID_A=$(sudo ovn-nbctl --data=bare --no-heading --columns=_uuid \
  create DHCP_Options cidr=10.0.1.0/24 \
  options="\"server_id\"=\"10.0.1.1\" \"server_mac\"=\"02:aa:aa:aa:aa:01\" \"lease_time\"=\"3600\" \"router\"=\"10.0.1.1\" \"dns_server\"=\"1.1.1.1\"")

# DHCP pour ls-B
UUID_B=$(sudo ovn-nbctl --data=bare --no-heading --columns=_uuid \
  create DHCP_Options cidr=10.0.2.0/24 \
  options="\"server_id\"=\"10.0.2.1\" \"server_mac\"=\"02:bb:bb:bb:bb:01\" \"lease_time\"=\"3600\" \"router\"=\"10.0.2.1\" \"dns_server\"=\"1.1.1.1\"")

# Lier les profils DHCP aux ports VM
sudo ovn-nbctl lsp-set-addresses vmA "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmA $UUID_A

sudo ovn-nbctl lsp-set-addresses vmB "dynamic"
sudo ovn-nbctl lsp-set-dhcpv4-options vmB $UUID_B
```

Sur les **compute1/2** :

```bash
sudo dhclient -v vmA-int    # sur compute1
sudo dhclient -v vmB-int    # sur compute2
```

✅ Chaque interface reçoit une IP (10.0.1.x / 10.0.2.x).

---

## 🧪 **5. Test de routage**

Depuis `compute1` :

```bash
ping -c3 10.0.2.10
```

✅ Réponses = routage logique OK
(`lr-AB` fonctionne, tunnel GENEVE OK)

---

## 🔐 **6. ACL (filtrage ICMP et HTTP)**

Sur **control** :

```bash
# Autoriser ICMP et TCP/80, bloquer le reste
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-A to-lport 0 "ip" drop

sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "icmp" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 1001 "tcp && tcp.dst==80" allow
sudo ovn-nbctl --may-exist acl-add ls-B to-lport 0 "ip" drop

sudo ovn-nbctl acl-list ls-A
```

✅ Ping et HTTP autorisés, autres flux bloqués.

---

## 🌍 **7. NAT (sortie + entrée)**

### Sur chaque compute :

```bash
sudo ovs-vsctl --may-exist add-br br-ex
sudo ovs-vsctl set open . external-ids:ovn-bridge-mappings=physnet1:br-ex
```

### Sur control :

```bash
# Switch externe + interface routeur
sudo ovn-nbctl ls-add ext-sw
sudo ovn-nbctl lsp-add ext-sw ext-local
sudo ovn-nbctl lsp-set-type ext-local localnet
sudo ovn-nbctl lsp-set-options ext-local network_name=physnet1

sudo ovn-nbctl lrp-add lr-AB lrp-ext 02:ee:ee:ee:ee:01 192.168.100.1/24
sudo ovn-nbctl lsp-add ext-sw ext-to-rtr
sudo ovn-nbctl lsp-set-type ext-to-rtr router
sudo ovn-nbctl lsp-set-addresses ext-to-rtr "02:ee:ee:ee:ee:01"
sudo ovn-nbctl lsp-set-options ext-to-rtr router-port=lrp-ext

# Routes et NAT
sudo ovn-nbctl lr-route-add lr-AB "0.0.0.0/0" 192.168.100.254
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.1.0/24
sudo ovn-nbctl lr-nat-add lr-AB snat 192.168.100.1 10.0.2.0/24
sudo ovn-nbctl lr-nat-add lr-AB dnat_and_snat 192.168.100.50 10.0.2.10
```

✅ Les VMs peuvent sortir (SNAT) et un service peut être exposé (DNAT).

---

## 🔍 **8. Contrôles de fin**

```bash
sudo ovn-nbctl show          # topologie NBDB
sudo ovn-nbctl acl-list ls-A # ACL actives
sudo ovn-sbctl show          # châssis
sudo ovn-sbctl lflow-list | head
sudo ovs-ofctl -O OpenFlow13 dump-flows br-int | head
```

---

✅ Si tous ces points sont bons :

* `ping` entre VMs fonctionne,
* ACL filtrent correctement,
* NAT fait sortir ou expose un service,
  alors **l’Atelier 2 est validé.**

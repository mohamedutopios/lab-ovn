Excellent 👏 — on va prolonger ton lab (qui est déjà parfait avec **vmA**, **vmB**, **ls-A**, **ls-B**, **lr-AB**, NAT + ACL**) pour en faire une **démonstration complète d’analyse et de diagnostic OVN**, exactement comme le feraient les ingénieurs réseaux pour comprendre le **plan de contrôle** et le **plan de données**.

---

# 🎯 Objectif pédagogique de cet atelier

Tu vas **apprendre à comprendre ce que fait OVN** quand un paquet circule :

* est-ce qu’il est **autorisé**, **routé**, **NATé**, ou **bloqué** ?
* pourquoi un flux **échoue** (ACL, NAT manquant, mauvais port logique, interface “down”, etc.) ?

Tu utiliseras deux outils :

| Outil            | Rôle                                                                               | Exécution                 |
| ---------------- | ---------------------------------------------------------------------------------- | ------------------------- |
| **`ovn-trace`**  | Simule un flux dans la base *Northbound* (plan de contrôle).                       | Sur le **control node**   |
| **`ovn-appctl`** | Observe et diagnostique ce que fait *localement* le démon `ovn-controller` et OVS. | Sur les **compute nodes** |

---

## 🧱 1. Rappel du lab utilisé

| Élément                      | Fonction                                              | Machine      |
| ---------------------------- | ----------------------------------------------------- | ------------ |
| **control (192.168.56.10)**  | OVN Central (`ovn-northd`, NBDB/SBDB)                 | Control node |
| **compute1 (192.168.56.11)** | VM **vmA**, IP **10.0.1.10**, Logical Switch **ls-A** | Compute1     |
| **compute2 (192.168.56.12)** | VM **vmB**, IP **10.0.2.10**, Logical Switch **ls-B** | Compute2     |
| **lr-AB**                    | Logical Router connectant les deux LS                 | Central      |
| **ls-ext + NAT**             | Externe 172.16.0.0/24, IP publique 172.16.0.100       | Central      |
| **ACLs**                     | ICMP + HTTP autorisés, reste bloqué                   | Central      |

---

# 🧩 2. Partie 1 : Analyse logique avec `ovn-trace` (plan de contrôle)

👉 À exécuter sur le **control node (192.168.56.10)**
(`ovn-trace` interroge la base Northbound via ovn-northd)

---

### 🔍 Exemple 1 — Flux autorisé : HTTP vmB → vmA

On simule un client (vmB) qui contacte le serveur (vmA) sur port 80.

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==80'
```

💡 Tu verras :

```
# Logical switch pipeline (ls-B):
  ... ACLs checked ...
  next; (allowed)
# Logical router pipeline (lr-AB):
  ... routing 10.0.2.0/24 -> 10.0.1.0/24 ...
  next; (DNAT? none)
# Logical switch pipeline (ls-A):
  output to "vmA"
  Verdict: allow
```

👉 **Interprétation :**

* ACL sur `ls-B` autorise le flux.
* Routage via `lr-AB`.
* Pas de NAT sur ce flux (interne ↔ interne).
* Sortie vers port logique `vmA` → ✅ autorisé.

---

### 🔍 Exemple 2 — Flux bloqué : HTTPS (443)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==443'
```

💡 Résultat :

```
drop; (ACL drop: priority 0)
```

👉 L’ACL “default drop” a bloqué le flux car pas de règle HTTP/80.

---

### 🔍 Exemple 3 — DNAT depuis Internet (172.16.0.100 → vmA)

```bash
ovn-trace ls-ext 'inport=="prov-uplink" && ip4.src==172.16.0.254 && ip4.dst==172.16.0.100 && tcp && tcp.dst==80'
```

💡 Résultat attendu :

```
lr-nat: dnat(172.16.0.100:80 -> 10.0.1.10:80)
output to "vmA"
```

👉 Le flux entrant est traduit en **DNAT** vers vmA → la translation est bien appliquée.

---

### 🔍 Exemple 4 — Hairpin NAT (vmB accède à vmA via IP publique)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==172.16.0.100 && tcp && tcp.dst==80'
```

💡 Résultat :

```
lr-nat: dnat_and_snat(172.16.0.100:80 -> 10.0.1.10:80)
output to "vmA"
```

👉 Le flux est **DNATé vers vmA** et **SNATé vers une IP du routeur** → le hairpin marche.

---

# 🧰 3. Partie 2 : Diagnostic local avec `ovn-appctl` (plan de données)

👉 À exécuter sur les **compute nodes** (`compute1`, `compute2`)

---

### 3.1. Inspecter les ports logiques vus localement

```bash
sudo ovn-appctl -t ovn-controller list Chassis_Private
sudo ovn-appctl -t ovn-controller list Port_Binding | grep -A2 vmA
sudo ovn-appctl -t ovn-controller list Port_Binding | grep -A2 vmB
```

💡 Tu verras les ports mappés localement, avec `up=true`.

---

### 3.2. Vérifier la connectivité logique (binding, up/down)

Sur **control** :

```bash
sudo ovn-sbctl --format=table --columns=logical_port,chassis,up list Port_Binding | egrep 'logical_port|chassis|up'
```

> `up=true` = le port est bien attaché (le tap `vnetX` est lié à `iface-id`).

---

### 3.3. Tracer un paquet réel (plan de données)

Sur **compute1** (où est vmA) :

```bash
# Voir les flux OVS correspondant à un port logique
sudo ovs-ofctl dump-flows br-int | grep vmA
```

Sur **compute2** (où est vmB) :

```bash
sudo ovs-ofctl dump-flows br-int | grep vmB
```

---

### 3.4. Inspecter le cache local des flows logiques

```bash
sudo ovn-appctl -t ovn-controller ofproto/trace br-int \
  'in_port=<ofport-vmB>,ip,nw_src=10.0.2.10,nw_dst=10.0.1.10,dl_type=0x800,tp_dst=80'
```

👉 Cela te montre le parcours exact du paquet **dans le datapath OVS local** (pas seulement la logique Northbound).

---

### 3.5. Rafraîchir les bindings et policies localement

Si un port semble inactif ou une ACL ne s’applique pas :

```bash
sudo ovn-appctl -t ovn-controller recompute
sudo ovn-appctl -t ovn-controller flush
```

---

# 🧠 4. Atelier pratique complet (pas à pas)

| Étape | Action                                | Outil       | Où                              | Objectif               |
| ----- | ------------------------------------- | ----------- | ------------------------------- | ---------------------- |
| 1     | `ping 10.0.1.10` depuis vmB           | `ovn-trace` | control                         | voir décision ICMP     |
| 2     | `curl http://10.0.1.10`               | `ovn-trace` | control                         | voir autorisation HTTP |
| 3     | `curl https://10.0.1.10`              | `ovn-trace` | control                         | voir “drop”            |
| 4     | `curl http://172.16.0.100` depuis vmB | `ovn-trace` | control                         | DNAT + hairpin         |
| 5     | `ovn-appctl ofproto/trace`            | compute2    | vérifier plan de données        |                        |
| 6     | `tcpdump -ni br-int`                  | compute1/2  | observer flux réels             |                        |
| 7     | `ovn-sbctl list Port_Binding`         | control     | vérifier port binding `up=true` |                        |
| 8     | `ovn-nbctl lr-nat-list lr-AB`         | control     | vérifier SNAT/DNAT actifs       |                        |

---

# 🎓 5. Points clés à retenir

✅ **`ovn-trace`** = simulation “logique” (décisions de la base NBDB/SBDB)
✅ **`ovn-appctl`** = introspection locale (ce qu’applique réellement OVS)
✅ **`ovs-ofctl dump-flows br-int`** = translation du plan de contrôle en OpenFlow
✅ **`tcpdump`** = observation du plan de données physique (paquets réels)

---

Souhaites-tu que je te génère un **TP complet d’analyse (énoncé + corrigé)** à partir de ce lab, avec :

* une série de **scénarios d’échec (ping bloqué, NAT absent, ACL drop)**,
* les **commandes de diagnostic ovn-trace / ovn-appctl / ovs-ofctl** correspondantes,
* et les **interprétations détaillées** ?
  Ce serait la version “pédagogique” de cet atelier d’analyse.

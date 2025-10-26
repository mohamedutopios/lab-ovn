Excellent 👏
Voici la version complète et didactique de ton :

# 🧩 **Atelier 3 – Analyse des flux avec OVN**

---

## 🎯 **Objectif**

Apprendre à **analyser, simuler et diagnostiquer** le comportement du plan de contrôle OVN à l’aide de :

* `ovn-trace` → pour simuler un flux logique dans la base Northbound.
* `ovn-appctl` → pour inspecter les flux réels et les décisions locales d’OVS/OVN.

Cet atelier permet de :

* comprendre *comment* OVN décide d’autoriser ou non un paquet (ACL, NAT, routage),
* identifier *pourquoi* un flux échoue (mauvaise ACL, NAT absent, port manquant, etc.).

---

## ⚙️ **Pré-requis**

L’**Atelier 2** est fonctionnel ✅
Tu disposes de :

* `ls-A`, `ls-B`, `lr-AB`
* Deux VMs simulées `vmA` (10.0.1.x) et `vmB` (10.0.2.x)
* Des ACL configurées (ICMP/HTTP autorisés)

---

## 🔍 **1. Vérifications avant analyse**

Sur `control` :

```bash
sudo ovn-nbctl show
sudo ovn-sbctl show
```

Sur un `compute` :

```bash
sudo ovs-vsctl show
```

✅ Tu dois voir `vmA` ou `vmB` liés à `br-int` avec leur `iface-id`.

---

## 🧪 **2. Simulation de flux avec `ovn-trace`**

### 📘 Syntaxe

```bash
sudo ovn-trace <logical_switch> '<conditions>'
```

Les conditions décrivent le paquet à simuler :

* `inport=="vmA"` → port logique source
* `ip` → protocole IP
* `icmp` ou `tcp` → type de paquet
* `nw_src=10.0.1.10`, `nw_dst=10.0.2.10` → IPs source/destination

---

### 💡 Exemple 1 – Simulation d’un ping ICMP autorisé

Sur **control** :

```bash
sudo ovn-trace ls-A 'inport=="vmA" && ip && icmp && nw_src==10.0.1.10 && nw_dst==10.0.2.10'
```

✅ **Résultat attendu (résumé)** :

```
Ingress table 0: LS_IN_PORT_SEC_L2: match ...
  => next
Ingress table 9: LS_IN_ACL: match (ip && icmp), priority 1001, action allow
...
Logical router pipeline ...
  output
```

➡️ Le flux est **autorisé** (`allow`) → ACL ICMP OK.

---

### 💡 Exemple 2 – Simulation d’un flux HTTP autorisé

```bash
sudo ovn-trace ls-A 'inport=="vmA" && ip && tcp && tcp.dst==80 && nw_src==10.0.1.10 && nw_dst==10.0.2.10'
```

✅ Le résultat doit contenir :

```
Ingress table 9: LS_IN_ACL: match (tcp && tcp.dst==80), action allow
```

---

### 💡 Exemple 3 – Flux bloqué (autre port TCP)

```bash
sudo ovn-trace ls-A 'inport=="vmA" && ip && tcp && tcp.dst==443 && nw_src==10.0.1.10 && nw_dst==10.0.2.10'
```

🔴 Résultat attendu :

```
Ingress table 9: LS_IN_ACL: match (ip), priority 0, action drop
```

➡️ Le flux est **bloqué par l’ACL** → comportement normal.

---

## ⚠️ **3. Exemples d’échecs à interpréter**

| Symptôme                                      | Cause probable                  | Vérification / commande                   |
| --------------------------------------------- | ------------------------------- | ----------------------------------------- |
| `ovn-trace` affiche `drop` dès table 0        | Port logique non trouvé         | `ovn-nbctl lsp-list`                      |
| `ovn-trace` affiche `drop` dans table 9 (ACL) | Règle manquante                 | `ovn-nbctl acl-list ls-A`                 |
| `ovn-trace` sort “NAT lookup failed”          | NAT non configuré               | `ovn-nbctl lr-nat-list lr-AB`             |
| Aucun “next” après table L2                   | Mauvais `inport` ou adresse MAC | Vérifie `ovn-nbctl lsp-get-addresses vmA` |
| Pas de routage                                | Router non connecté             | `ovn-nbctl lr-list`, `ovn-nbctl show`     |

---

## 🧠 **4. Inspection locale avec `ovn-appctl`**

Les flux logiques simulés par `ovn-trace` deviennent **des flux OpenFlow** injectés dans OVS.
On peut les inspecter sur chaque `compute`.

### 🔍 Lister les connexions actives OVN

```bash
sudo ovn-appctl -t ovn-controller connection-status
```

✅ Doit afficher :

```
northd_connection: connected
sb_connection: connected
```

### 🔍 Inspecter le cache des ports locaux

```bash
sudo ovn-appctl -t ovn-controller ovs-interface-list
```

Permet de vérifier que `vmA-int` ou `vmB-int` est bien reconnu comme port logique.

---

## ⚙️ **5. Analyser les flux OpenFlow réellement installés**

Sur `compute1` :

```bash
sudo ovs-ofctl -O OpenFlow13 dump-flows br-int | head
```

Tu verras des tables de flux générées par OVN (`priority=... actions=...`) correspondant à :

* ACL,
* NAT,
* routage logique.

---

## 🔎 **6. Exemple complet d’analyse d’erreur NAT**

Si un `ping` vers Internet échoue :

1. Vérifie la règle NAT :

   ```bash
   sudo ovn-nbctl lr-nat-list lr-AB
   ```

   ✅ Doit contenir `snat 192.168.100.1 10.0.1.0/24`.

2. Simule le flux :

   ```bash
   sudo ovn-trace lr-AB 'inport=="lrp-AB-A" && ip && nw_src==10.0.1.10 && nw_dst==8.8.8.8'
   ```

   🔎 Si le NAT est manquant, tu verras :
   `No match found in lr_in_nat stage → drop`.

---

## 🧩 **7. Résumé des commandes utiles**

| Action                   | Commande                                                      |
| ------------------------ | ------------------------------------------------------------- |
| Simulation d’un ping     | `ovn-trace ls-A 'inport=="vmA" && icmp && nw_dst==10.0.2.10'` |
| Simulation HTTP          | `ovn-trace ls-A 'inport=="vmA" && tcp && tcp.dst==80'`        |
| Simulation refusée (443) | `ovn-trace ls-A 'inport=="vmA" && tcp && tcp.dst==443'`       |
| Vérifier les ACL         | `ovn-nbctl acl-list ls-A`                                     |
| Vérifier NAT             | `ovn-nbctl lr-nat-list lr-AB`                                 |
| Flux installés (OVS)     | `ovs-ofctl dump-flows br-int`                                 |
| Inspection locale OVN    | `ovn-appctl -t ovn-controller connection-status`              |

---

## ✅ **Validation de l’Atelier 3**

| Test               | Commande                                         | Résultat attendu   |
| ------------------ | ------------------------------------------------ | ------------------ |
| Simulation ICMP    | `ovn-trace … icmp …`                             | action allow       |
| Simulation TCP/80  | `ovn-trace … tcp.dst==80`                        | action allow       |
| Simulation TCP/443 | `ovn-trace … tcp.dst==443`                       | action drop        |
| Vérif NAT          | `ovn-nbctl lr-nat-list lr-AB`                    | SNAT/DNAT présents |
| Contrôleur local   | `ovn-appctl -t ovn-controller connection-status` | connected          |

---

🟢 **Si tous ces tests donnent les résultats attendus**,
tu maîtrises désormais :

* la visualisation du plan logique OVN,
* la simulation complète d’un flux réseau,
* le diagnostic des ACL et du NAT.

👉 Atelier 4 (prochain) pourra aborder **le debug approfondi et la supervision d’OVN/OVS avec logs et métriques**.

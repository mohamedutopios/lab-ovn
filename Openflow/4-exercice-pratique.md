Parfait Mohamed 💪 — tu veux maintenant compléter ton lab OVN avec **un atelier de diagnostic réseau complet**, orienté **plan de contrôle + plan de données**.
On garde **exactement la même architecture** (control, compute1, compute2, vmA, vmB, NAT, ACL, QoS…), et on va apprendre à **déboguer tout le pipeline OVN** de façon méthodique, avec les outils natifs.

---

# 🎯 Objectif de l’atelier : Diagnostic réseau complet OVN

Tu vas apprendre à :

1. Utiliser les outils d’inspection (`ovn-trace`, `ovn-sbctl`, `ovn-appctl`, `ovs-ofctl`, `journalctl`)
2. Suivre les **étapes de diagnostic** du réseau logique → physique.
3. Identifier la **source d’une panne** : ACL, NAT, tunnel, binding, port inactif, etc.
4. Comprendre **comment corriger** chaque type de problème.

---

# 🧱 1. Topologie du lab (rappel)

| Rôle               | Nom                              | IP                              | Rattachement                      |
| ------------------ | -------------------------------- | ------------------------------- | --------------------------------- |
| **OVN Central**    | `control`                        | 192.168.56.10                   | `ovn-northd`, NB/SB DB            |
| **Compute1**       | `compute1`                       | 192.168.56.11                   | héberge `vmA` (10.0.1.10, `ls-A`) |
| **Compute2**       | `compute2`                       | 192.168.56.12                   | héberge `vmB` (10.0.2.10, `ls-B`) |
| **Router logique** | `lr-AB`                          | 10.0.1.1 / 10.0.2.1             | connecte `ls-A` et `ls-B`         |
| **br-int**         | Bridge d’intégration interne OVN | Tous les computes               |                                   |
| **br-ex**          | Bridge externe (NAT)             | Expose IP publique 172.16.0.100 |                                   |

---

# 🧰 2. Outils de diagnostic OVN

| Outil                     | Niveau                           | Utilisation principale                       |
| ------------------------- | -------------------------------- | -------------------------------------------- |
| **`ovn-nbctl`**           | Northbound DB (plan logique)     | Vérifie les LS/LR, ACLs, NAT                 |
| **`ovn-sbctl`**           | Southbound DB (plan de contrôle) | Vérifie les bindings, chassis, logical flows |
| **`ovn-trace`**           | Simulation logique complète      | Teste le traitement d’un flux                |
| **`ovn-appctl`**          | Agent local (`ovn-controller`)   | Voir les flux réels, OpenFlow, cache local   |
| **`ovs-ofctl`**           | Plan de données (OVS)            | Dump des règles et ports sur `br-int`        |
| **`journalctl -u ovn-*`** | Logs système                     | Déboguer northd, controller, DBs             |

---

# 🧩 3. Étapes de diagnostic réseau OVN

## 🥇 Étape 1 — Vérifier les bases de données NB/SB

👉 Sur **control (192.168.56.10)**

### Vérifier que les bases sont en écoute

```bash
sudo ss -ltnp | grep -E '6641|6642'
```

→ tu dois voir :

```
tcp   LISTEN 0 128 0.0.0.0:6641  # ovn-nb
tcp   LISTEN 0 128 0.0.0.0:6642  # ovn-sb
```

### Vérifier la cohérence des objets logiques

```bash
sudo ovn-nbctl show
sudo ovn-sbctl show
```

💡 À vérifier :

* Les **Logical Switches** : `ls-A`, `ls-B`, `ls-ext`
* Le **Logical Router** : `lr-AB`
* Les **ports logiques** (`vmA`, `vmB`) → doivent être présents et "up".

---

## 🥈 Étape 2 — Vérifier les bridges `br-int` / `br-ex`

👉 Sur chaque **compute**

### Voir les bridges et interfaces

```bash
sudo ovs-vsctl show
```

→ tu dois voir :

```
Bridge "br-int"
    Port "vnet3"  (vmA)
    Port "genev_sys_6081"
Bridge "br-ex"
    Port "br-ex"
```

### Vérifier que le bridge d’intégration est fonctionnel

```bash
sudo ovs-vsctl list bridge
sudo ovs-ofctl dump-ports br-int
```

💡 Vérifie :

* `br-int` contient bien `vnetX` et `patch` vers tunnel (`genev_sys_6081`).
* Pas d’erreurs de port inactif ou `ofport=-1`.

---

## 🥉 Étape 3 — Vérifier les tunnels Geneve

👉 Toujours sur les **compute nodes**

### Lister les interfaces Geneve

```bash
sudo ovs-vsctl list interface | grep -A3 genev_sys
```

Exemple attendu :

```
name                : genev_sys_6081
type                : geneve
options             : {remote_ip="192.168.56.12", key=flow}
```

💡 Si `remote_ip` manquant ou erroné → problème de tunnel.

### Vérifier la connectivité entre computes

```bash
ping -c3 192.168.56.11
ping -c3 192.168.56.12
```

---

## 🧱 Étape 4 — Vérifier les flux logiques (SBDB)

👉 Sur **control**

Lister tous les **logical flows** compilés par OVN :

```bash
sudo ovn-sbctl lflow-list
```

Filtrer par un Logical Switch :

```bash
sudo ovn-sbctl lflow-list | grep ls-B -A3
```

Tu verras des règles du type :

```
table=0 (ls_in_port_sec_l2), priority=50, match=(inport == "vmB"), action=next;
table=65 (ls_out_acl), priority=1001, match=(ip4 && tcp && tcp.dst == 22), action=allow;
```

---

## 🧱 Étape 5 — Vérifier les règles OpenFlow (datapath)

👉 Sur **compute1** ou **compute2**

### Dump des flux OpenFlow sur `br-int`

```bash
sudo ovs-ofctl dump-flows br-int | head -20
```

Cherche des lignes avec :

* `priority`
* `match`
* `actions=resubmit(...)`
  → elles représentent le pipeline OpenFlow généré par OVN.

### Vérifie la cohérence avec les ACLs / NAT

Exemple :

```bash
sudo ovs-ofctl dump-flows br-int | grep tcp
sudo ovs-ofctl dump-flows br-int | grep nat
sudo ovs-ofctl dump-flows br-int | grep drop
```

---

## 🧱 Étape 6 — Vérifier ACLs et NAT

👉 Sur **control**

### ACLs

```bash
ovn-nbctl acl-list ls-B
```

### NAT

```bash
ovn-nbctl lr-nat-list lr-AB
```

Tu dois voir :

```
TYPE             EXTERNAL_IP     LOGICAL_IP
dnat_and_snat    172.16.0.100    10.0.1.10
snat             172.16.0.100    10.0.0.0/16
```

---

## 🧱 Étape 7 — Simuler un flux logique avec `ovn-trace`

👉 Sur **control**

### Exemple 1 : HTTP (autorisé)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==80'
```

### Exemple 2 : ICMP (bloqué par ACL)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && icmp4'
```

### Exemple 3 : DNAT externe

```bash
ovn-trace ls-ext 'inport=="prov-uplink" && ip4.src==172.16.0.254 && ip4.dst==172.16.0.100 && tcp && tcp.dst==80'
```

---

## 🧱 Étape 8 — Vérifier le plan de contrôle local

👉 Sur **compute nodes**

### Voir les flux OpenFlow gérés localement par OVN Controller

```bash
sudo ovn-appctl -t ovn-controller ofctrl/dump-flows
```

### Voir la liste des bindings locaux

```bash
sudo ovn-appctl -t ovn-controller list Port_Binding | grep -A3 vm
```

💡 Si un port logique n’a pas de chassis associé → il n’est pas “bound” → donc inactif.

---

## 🧱 Étape 9 — Vérifier les logs (journalctl)

👉 Sur chaque machine

### OVN Northd (control)

```bash
sudo journalctl -u ovn-northd -f
```

### OVN Controller (compute)

```bash
sudo journalctl -u ovn-controller -f
```

### Bases de données

```bash
sudo journalctl -u ovn-northd -u ovn-controller -u openvswitch-switch --since "5 minutes ago"
```

💡 Les logs te montreront les messages de binding, les règles recréées ou supprimées, et les erreurs de tunnel Geneve.

---

# 🧠 10. Méthode de diagnostic complète (résumé)

| Étape | Vérification   | Commande clé                                    | Interprétation                 |                |
| ----- | -------------- | ----------------------------------------------- | ------------------------------ | -------------- |
| 1️⃣   | NB/SB DB       | `ovn-nbctl show`, `ovn-sbctl show`              | Topologie logique OK           |                |
| 2️⃣   | Bridges        | `ovs-vsctl show`, `ovs-ofctl dump-ports br-int` | Ports présents, up             |                |
| 3️⃣   | Tunnel Geneve  | `ovs-vsctl list interface                       | grep genev_sys`                | Tunnels actifs |
| 4️⃣   | Flux logiques  | `ovn-sbctl lflow-list`                          | Compilation correcte           |                |
| 5️⃣   | Flux physiques | `ovs-ofctl dump-flows br-int`                   | Règles OpenFlow présentes      |                |
| 6️⃣   | ACL/NAT        | `ovn-nbctl acl-list`, `ovn-nbctl lr-nat-list`   | Contrôle des autorisations     |                |
| 7️⃣   | Simulation     | `ovn-trace 'flux'`                              | Vérification du chemin logique |                |
| 8️⃣   | Plan local     | `ovn-appctl ofctrl/dump-flows`                  | Flux réellement poussés        |                |
| 9️⃣   | Logs           | `journalctl -u ovn-*`                           | Messages d’erreur et d’état    |                |

---

# 🧪 11. Scénario de panne simulé (pour démo)

| Scénario                  | Symptôme                   | Diagnostic                                                   | Correction                                    |
| ------------------------- | -------------------------- | ------------------------------------------------------------ | --------------------------------------------- |
| Port logique `vmB` non up | Ping impossible            | `ovn-sbctl list Port_Binding` → `up=false`                   | Vérifie `external-ids:iface-id`               |
| Tunnel Geneve coupé       | Plus de trafic inter-host  | `ovs-vsctl list interface genev_sys_6081` → pas de remote_ip | Vérifie `ovn-encap-ip`                        |
| ACL drop ICMP             | Ping KO                    | `ovn-nbctl acl-list ls-B` → drop icmp4                       | Supprime ou ajuste l’ACL                      |
| NAT manquant              | `curl 172.16.0.100` échoue | `ovn-nbctl lr-nat-list` → vide                               | Recrée SNAT/DNAT                              |
| OVS désynchronisé         | Règles OpenFlow absentes   | `ovs-ofctl dump-flows br-int` vide                           | `sudo ovn-appctl -t ovn-controller recompute` |

---

Souhaites-tu que je t’ajoute maintenant la **version TP guidé (avec panne simulée)** où :

1. on casse un composant (ACL, tunnel ou NAT),
2. on diagnostique avec ces outils,
3. on corrige ?
   Cela permet d’avoir un atelier “troubleshooting OVN complet” pour formation.

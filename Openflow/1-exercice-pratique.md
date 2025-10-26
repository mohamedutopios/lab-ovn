Excellent 💪 — on continue dans **ton même lab OVN complet** (avec `control`, `compute1`, `compute2`, `vmA`, `vmB`, NAT, ACL, QoS, etc.) et on va maintenant **plonger dans la mécanique interne du SDN**, c’est-à-dire **OpenFlow**.
C’est une démo fondamentale pour comprendre *comment OVN transforme ses objets logiques (Logical Switch, Router, ACL…)* en *règles OpenFlow physiques* installées sur les bridges (`br-int`, etc.).

---

# 🎯 Objectif du module : "OpenFlow dans OVN"

Ce module te permet de :

* comprendre le **rôle d’OpenFlow** dans un environnement SDN/OVN,
* voir **comment OVN compile automatiquement** les flux logiques en règles OpenFlow,
* apprendre à **lire et interpréter** les tables OpenFlow dans `br-int`,
* faire un **exercice concret** : supprimer une règle OpenFlow et observer la perte de connectivité,
* puis **reconstruire** les flux via `ovn-controller`.

---

# 🧠 1. Rappel de concept : SDN, OVS et OpenFlow

| Élément                               | Rôle                                                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **SDN (Software Defined Networking)** | Séparation du plan de contrôle (décisions) et du plan de données (acheminement).                                                       |
| **OVS (Open vSwitch)**                | Commutateur virtuel gérant le plan de données, programmable via OpenFlow.                                                              |
| **OpenFlow**                          | Protocole standard de contrôle des flux : définit quelles actions exécuter sur les paquets (match, priorité, actions).                 |
| **OVN (Open Virtual Network)**        | Surcouche d’OVS qui automatise la génération des règles OpenFlow à partir des objets logiques (Logical Switches, Routers, ACLs, NATs). |

👉 OVN agit comme un **compilateur** :
Les objets de la **base Northbound (NBDB)** sont traduits en **règles OpenFlow dans OVS** par le **ovn-controller** sur chaque nœud.

---

# ⚙️ 2. Où regarder dans ton lab

| Rôle        | Machine                    | Bridge concerné                |
| ----------- | -------------------------- | ------------------------------ |
| OVN Central | `control` (192.168.56.10)  | (aucun flux utile ici)         |
| Compute 1   | `compute1` (192.168.56.11) | `br-int` (où est branchée vmA) |
| Compute 2   | `compute2` (192.168.56.12) | `br-int` (où est branchée vmB) |

Toutes les règles OpenFlow **sont visibles sur les computes**, dans **`br-int`**.

---

# 🔍 3. Lecture de la table OpenFlow

👉 Sur **compute1** ou **compute2** :

```bash
sudo ovs-ofctl dump-flows br-int
```

Tu verras une sortie du type :

```
cookie=0x0, duration=231.12s, table=0, n_packets=12, n_bytes=1008, priority=100, match:in_port=1, actions=resubmit(,4)
cookie=0x0, duration=231.11s, table=4, n_packets=12, n_bytes=1008, priority=50, match:ip,nw_dst=10.0.1.10, actions=output:2
...
```

---

# 📖 4. Comment interpréter les champs

| Champ                                    | Description                                                                               |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- |
| **table**                                | Numéro de table OpenFlow (chaque fonction OVN a ses tables : ingress, egress, ACL, NAT…). |
| **priority**                             | Priorité du flux (plus haut = plus prioritaire).                                          |
| **match**                                | Condition d’activation du flux (`ip`, `tcp`, `in_port=`, `nw_dst=`, etc.).                |
| **actions**                              | Action exécutée : `output:port`, `resubmit(,table)`, `drop`, `ct(...)`, `nat(...)`, etc.  |
| **cookie**                               | Identifiant logique du flux (souvent 0x0).                                                |
| **duration**, **n_packets**, **n_bytes** | Statistiques (utile pour voir les flux actifs).                                           |

---

# 🧩 5. Cartographie entre objets logiques et flux OpenFlow

| Objet logique OVN  | Traduction OpenFlow                   | Table(s) typique(s) |                          |       |
| ------------------ | ------------------------------------- | ------------------- | ------------------------ | ----- |
| **Logical Switch** | L2 switching, ARP, MAC learning, ACLs | 0–49                |                          |       |
| **Logical Router** | Routage, NAT, conntrack               | 60–89               |                          |       |
| **ACLs**           | Règles `ct.est                        |                     | ct.rel`, `drop`, `allow` | 66–69 |
| **QoS**            | `set_queue`, `rate_limit`             | 70–80               |                          |       |
| **Localnet/NAT**   | `ct(nat)`, `dnat`, `snat`             | 70–80               |                          |       |

> OVN empile donc plusieurs tables OpenFlow dans `br-int` pour refléter le pipeline logique de ton topologie.

---

# 🧠 6. Exemple concret dans ton lab

### Cas : flux HTTP de vmB → vmA (10.0.2.10 → 10.0.1.10:80)

Sur `compute2` :

```bash
sudo ovs-ofctl dump-flows br-int | grep 10.0.1.10
```

💡 Tu verras :

* table 0 : match in_port de vmB
* table 4 : routage logique vers vmA
* table 33 : ACL allow (HTTP)
* table 40–60 : output vers port logique vmA (via Geneve)

---

# 🔬 7. Exercice pratique (diagnostic et suppression de règle)

## Étape 1 — vérifier le flux logique

Depuis **vmB** :

```bash
curl -I http://10.0.1.10
```

→ HTTP fonctionne.

## Étape 2 — identifier la règle responsable

Sur **compute2** :

```bash
sudo ovs-ofctl dump-flows br-int | grep tcp
```

Cherche la règle avec :

```
match: ip, tcp, nw_dst=10.0.1.10, tp_dst=80
actions=...
```

Note son `cookie` et sa `table`.

## Étape 3 — supprimer la règle (volontairement)

Exemple :

```bash
sudo ovs-ofctl del-flows br-int "table=4,tcp,nw_dst=10.0.1.10,tp_dst=80"
```

## Étape 4 — tester à nouveau

```bash
curl -I http://10.0.1.10
```

➡️ Le flux échoue : plus de correspondance OpenFlow → plus de routage.

## Étape 5 — forcer la régénération

```bash
sudo ovn-appctl -t ovn-controller recompute
```

Puis re-teste :

```bash
curl -I http://10.0.1.10
```

➡️ Fonctionne à nouveau : le **ovn-controller** a régénéré les règles à partir de la base logique (NBDB/SBDB).

---

# 🔧 8. Diagnostic avancé

## Vérifier le mapping entre ports physiques et logiques

```bash
sudo ovs-vsctl list interface | grep external_ids -A2
```

## Voir les flux NAT et conntrack

```bash
sudo ovs-ofctl dump-flows br-int | grep -E 'ct|nat'
```

## Visualiser la pipeline complète

```bash
sudo ovs-ofctl dump-tables br-int
```

---

# 🧰 9. Résumé pédagogique

| Action                    | Commande                                  | Lieu              | Résultat                           |
| ------------------------- | ----------------------------------------- | ----------------- | ---------------------------------- |
| Lire les flux             | `ovs-ofctl dump-flows br-int`             | compute           | Toutes les règles actives          |
| Identifier les tables     | `ovs-ofctl dump-tables br-int`            | compute           | Tables logiques OVN                |
| Supprimer une règle       | `ovs-ofctl del-flows br-int ...`          | compute           | Perte de connectivité ciblée       |
| Régénérer les règles      | `ovn-appctl -t ovn-controller recompute`  | compute           | Recréation auto depuis OVN         |
| Corréler logique/physique | `ovn-nbctl show` ↔ `ovs-ofctl dump-flows` | control + compute | Compréhension complète du pipeline |

---

# 🧩 10. Variante d’analyse complémentaire

Depuis **control** :

```bash
# Flux logique simulé (plan de contrôle)
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==80'
```

Puis sur **compute2** :

```bash
# Flux physique appliqué (plan de données)
sudo ovs-ofctl dump-flows br-int | grep 10.0.1.10
```

➡️ Tu compares ainsi **le flux logique “décidé”** (ovn-trace) et **le flux physique “installé”** (OpenFlow).

---

Souhaites-tu que je t’ajoute la **suite du module** sur la **visualisation complète du pipeline OpenFlow (diagramme de tables 0–80 avec explication)** pour que tes apprenants puissent suivre la chaîne complète *du flux logique OVN jusqu’à l’action OpenFlow* ?

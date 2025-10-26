Excellent 💪 — tu arrives maintenant à la **dernière brique de ton lab OVN complet** : la **supervision et maintenance via les logs + bonnes pratiques d’exploitation**.
Cette partie complète la supervision Prometheus/Grafana, en te donnant les **réflexes d’admin réseau OVN** pour auditer, sauvegarder, corriger et prévenir les erreurs du plan de contrôle et de données.

---

# 🧭 **Objectif du module : Logs & bonnes pratiques d’exploitation OVN**

Tu vas apprendre à :

1. Identifier les **fichiers de log critiques** (OVS et OVN).
2. Surveiller en temps réel les comportements anormaux (chassis down, tunnel cassé, drop massif).
3. Mettre en place une **politique de maintenance préventive** :

   * sauvegarde régulière des bases NB/SB,
   * vérification de cohérence,
   * convention de nommage stricte des ressources.

---

# 🧱 1. Logs à connaître et à surveiller

| Service                 | Fichier                                   | Localisation          | Contenu principal                                           |
| ----------------------- | ----------------------------------------- | --------------------- | ----------------------------------------------------------- |
| **Open vSwitch daemon** | `/var/log/openvswitch/ovs-vswitchd.log`   | Sur tous les computes | Plan de données : interfaces, tunnels, OpenFlow, QoS        |
| **OVN Controller**      | `/var/log/openvswitch/ovn-controller.log` | Sur chaque compute    | Plan de contrôle local : binding, flows, synchronisation    |
| **OVN Northd**          | `/var/log/openvswitch/ovn-northd.log`     | Sur le control node   | Plan de traduction logique : génération des flows OpenFlow  |
| **OVN Databases**       | `/var/log/openvswitch/ovsdb-server.log`   | Sur le control node   | Transactions sur NBDB/SBDB, erreurs de schema ou corruption |

---

## 🧩 1.1 Exemples de messages utiles

### 🔹 `ovs-vswitchd.log`

```text
2025-10-27T20:10:54.110Z|00002|netdev_geneve|INFO|interface genev_sys_6081: remote_ip=192.168.56.12 key=flow
2025-10-27T20:10:55.213Z|00003|bridge|WARN|Port vnet3: link down
2025-10-27T20:10:56.314Z|00004|ofproto_dpif_upcall|INFO|Added flow (in_port=1,actions=output:2)
```

🧠 *Interprétation :*

* création d’un tunnel geneve
* port VM déconnecté
* insertion d’une règle OpenFlow

---

### 🔹 `ovn-controller.log`

```text
2025-10-27T20:12:17.452Z|00001|binding|INFO|Claimed logical port 'vmA' on chassis compute1
2025-10-27T20:12:18.091Z|00002|lflow|INFO|Installed 122 logical flows on br-int
2025-10-27T20:12:19.200Z|00003|binding|WARN|Logical port vmB: chassis mismatch, rebind needed
```

🧠 *Interprétation :*

* Le port `vmA` a été lié correctement à compute1.
* 122 règles logiques traduites en OpenFlow sur br-int.
* `vmB` a été détecté sur un mauvais hôte (souvent après reboot → problème `system-id`).

---

### 🔹 `ovn-northd.log`

```text
2025-10-27T20:15:00.501Z|00005|ovn_northd|INFO|Recomputed logical flows for lr-AB (changes in ACLs)
2025-10-27T20:15:01.611Z|00006|ovn_northd|WARN|Inconsistent LSP binding: vmB (no chassis)
```

🧠 *Interprétation :*

* Recalcul logique suite à changement d’ACL.
* Un port n’a pas de binding → `up=false`.

---

### 🔹 `ovsdb-server.log`

```text
2025-10-27T20:17:01.512Z|00001|jsonrpc|INFO|connection from 127.0.0.1:6641
2025-10-27T20:17:05.612Z|00002|ovsdb|WARN|transaction commit failed: duplicate UUID
```

🧠 *Interprétation :*

* Connexion du client OVN vers la DB.
* Problème de transaction (souvent causé par duplication d’objet après crash).

---

## 🧩 1.2 Commandes de suivi en temps réel

### Sur tous les nœuds

```bash
sudo tail -f /var/log/openvswitch/ovs-vswitchd.log
sudo tail -f /var/log/openvswitch/ovn-controller.log
```

### Sur le control node

```bash
sudo tail -f /var/log/openvswitch/ovn-northd.log
sudo tail -f /var/log/openvswitch/ovsdb-server.log
```

---

## 🧩 1.3 Astuce : filtrer par gravité

OVN/OVS utilisent des niveaux syslog classiques (`INFO`, `WARN`, `ERR`).
Tu peux filtrer uniquement les erreurs :

```bash
grep ERR /var/log/openvswitch/*.log
grep WARN /var/log/openvswitch/*.log
```

Ou créer un alias permanent :

```bash
alias ovnlog='grep -E "ERR|WARN" /var/log/openvswitch/*.log --color'
```

---

# 🧠 2. Bonnes pratiques d’administration OVN

---

## 🗄️ 2.1 Sauvegarde régulière des bases NBDB/SBDB

Les bases sont stockées sur le **control node** :

```
/var/lib/ovn/ovnnb_db.db
/var/lib/ovn/ovnsb_db.db
```

### Sauvegarde quotidienne automatisée :

```bash
sudo mkdir -p /var/backups/ovn
sudo ovsdb-client dump tcp:127.0.0.1:6641 > /var/backups/ovn/nbdb-$(date +%F).dump
sudo ovsdb-client dump tcp:127.0.0.1:6642 > /var/backups/ovn/sbdb-$(date +%F).dump
```

💡 **Astuce :**
mets ces lignes dans un `cron.daily` :

```bash
sudo crontab -e
```

```cron
0 2 * * * /usr/bin/ovsdb-client dump tcp:127.0.0.1:6641 > /var/backups/ovn/nbdb-$(date +\%F).dump
0 2 * * * /usr/bin/ovsdb-client dump tcp:127.0.0.1:6642 > /var/backups/ovn/sbdb-$(date +\%F).dump
```

---

## 🔍 2.2 Vérification de cohérence des chassis

### Depuis le **control node**

```bash
sudo ovn-sbctl chassis-list
```

Exemple :

```
hostname : compute1
encaps   : geneve 192.168.56.11
uuid     : 1234-abcd

hostname : compute2
encaps   : geneve 192.168.56.12
uuid     : 5678-efgh
```

💡 Bon signe :

* Les deux computes sont bien enregistrés.
* Les IPs d’encapsulation (Geneve) sont correctes.

### Si tu vois un chassis “inconnu” :

```bash
sudo ovn-sbctl chassis-del <uuid>
```

Puis redémarre `ovn-controller` sur le compute concerné :

```bash
sudo systemctl restart ovn-controller
```

---

## 🧾 2.3 Politique de nommage claire

**Pourquoi ?**
OVN est sensible aux noms : ils sont utilisés dans les bindings et les logs (`lsp-add`, `lrp-add`, etc.).
Une incohérence peut casser le pipeline.

### Règles de base à appliquer

| Type                         | Bon format              | Exemple                  |
| ---------------------------- | ----------------------- | ------------------------ |
| **Logical Switches**         | `ls-<zone>`             | `ls-A`, `ls-B`, `ls-ext` |
| **Routers**                  | `lr-<zone1>-<zone2>`    | `lr-AB`                  |
| **Ports logiques (VM)**      | `vm<Nom>`               | `vmA`, `vmB`             |
| **Ports router**             | `lrp-<router>-<switch>` | `lrp-AB-A`               |
| **Ports switch côté router** | `lsp-<switch>-lr`       | `lsp-A-lr`               |
| **Bridges OVS**              | `br-<fonction>`         | `br-int`, `br-ex`        |

💡 *Exemple concret de cohérence :*

```
lr-AB
 ├── lrp-AB-A (10.0.1.1)
 ├── lrp-AB-B (10.0.2.1)
ls-A
 ├── lsp-A-lr ↔ lrp-AB-A
 └── vmA (10.0.1.10)
ls-B
 ├── lsp-B-lr ↔ lrp-AB-B
 └── vmB (10.0.2.10)
```

---

## 🧩 2.4 Vérification de la santé générale

Tu peux rapidement faire un check global :

```bash
echo "🔍 Vérification OVN :"
ovn-sbctl show | grep -E 'hostname|encap|up|false|drop'
ovn-nbctl show | grep -E 'ls|lr|port'
sudo ovs-vsctl show | grep -E 'br-|Port|Interface'
```

---

## 🧠 2.5 Logs et supervision combinée

Associe **les logs à Prometheus/Grafana** :

* Ajoute `/var/log/openvswitch/*.log` dans ton agent `promtail` (si tu veux Loki).
* Visualise les `WARN` et `ERR` directement dans Grafana Logs Explorer.

---

# 🧩 3. Résumé pour ton lab

| Catégorie                 | Emplacement                                                | Commande / action           | Fréquence  |
| ------------------------- | ---------------------------------------------------------- | --------------------------- | ---------- |
| **Logs runtime (OVS)**    | `/var/log/openvswitch/ovs-vswitchd.log`                    | `tail -f` / `grep WARN`     | en continu |
| **Logs plan de contrôle** | `/var/log/openvswitch/ovn-controller.log`                  | audit binding/flows         | en continu |
| **Logs northd / DB**      | `/var/log/openvswitch/ovn-northd.log` / `ovsdb-server.log` | recalculs, erreurs DB       | quotidien  |
| **Sauvegardes DB**        | `/var/backups/ovn/`                                        | `ovsdb-client dump`         | quotidien  |
| **Cohérence chassis**     | `ovn-sbctl chassis-list`                                   | comparer UUID/IP            | hebdo      |
| **Nettoyage**             | `ovn-sbctl chassis-del <uuid>`                             | après crash / duplication   | si besoin  |
| **Convention de nommage** | `ls-*`, `lr-*`, `vm*`                                      | respecter structure logique | toujours   |

---

Souhaites-tu que je t’ajoute juste après cela un **TP “audit et maintenance OVN”** où les apprenants doivent :

1. retrouver une erreur dans les logs,
2. corriger une incohérence de chassis,
3. effectuer une sauvegarde/restauration de DB ?

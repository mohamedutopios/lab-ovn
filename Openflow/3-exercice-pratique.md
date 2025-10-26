Excellent 🔥 — on va maintenant ajouter un **atelier complet sur les ACLs (Access Control Lists)** dans **ton lab OVN existant** (avec `control`, `compute1`, `compute2`, `vmA`, `vmB`, `lr-AB`).

Cet atelier est parfait pour comprendre :

* la **syntaxe exacte** des ACLs OVN (`match`, `priority`, `direction`, `action`),
* leur **sens d’application (from-lport / to-lport)**,
* la **gestion des priorités**,
* et comment **auditer et tracer** les décisions (logs OVN).

---

# 🎯 Objectif du module

Tu vas :

1. Apprendre le **format et le sens** des ACLs dans OVN.
2. Appliquer des ACLs sur un logical switch (`ls-B`).
3. Tester :

   * blocage ICMP,
   * autorisation SSH uniquement (TCP/22),
   * refus par défaut du reste.
4. Consulter les **logs et traces** pour auditer les décisions.

---

# 🧩 1. Rappel de topologie du lab

| Élément | Rôle            | IP                  | Localisation       |
| ------- | --------------- | ------------------- | ------------------ |
| `vmA`   | Serveur cible   | 10.0.1.10           | `compute1`, `ls-A` |
| `vmB`   | Client          | 10.0.2.10           | `compute2`, `ls-B` |
| `lr-AB` | Routeur logique | 10.0.1.1 / 10.0.2.1 | Control            |

Les VMs peuvent se ping et communiquer via le routeur logique `lr-AB`.

---

# 🧠 2. Format d’une ACL OVN

```bash
ovn-nbctl acl-add <logical-switch> <direction> <priority> <match> <action>
```

| Paramètre          | Explication                                                                           |
| ------------------ | ------------------------------------------------------------------------------------- |
| `<logical-switch>` | Le LS où on applique la règle (ex : `ls-B`).                                          |
| `<direction>`      | `from-lport` (trafic **sortant** du port logique) ou `to-lport` (trafic **entrant**). |
| `<priority>`       | Nombre (0–32767). Plus grand = plus prioritaire.                                      |
| `<match>`          | Expression logique sur les champs IP, protocole, port, etc.                           |
| `<action>`         | `allow`, `allow-related`, `drop`, `reject`, `allow-stateless`.                        |

---

# ⚙️ 3. Préparation : suppression des ACL existantes

👉 Sur le **control node (192.168.56.10)**

```bash
# Nettoyer toutes les ACL sur les deux switches
ovn-nbctl acl-del ls-A
ovn-nbctl acl-del ls-B
```

---

# 🚧 4. Application des ACLs

### Objectif :

* 🔴 **Bloquer ICMP**
* 🟢 **Autoriser SSH (port 22)**
* ⚫ **Refuser tout le reste**

👉 Toujours sur le **control node** :

```bash
# 1️⃣ Autoriser SSH (port 22)
ovn-nbctl acl-add ls-B from-lport 1002 'ip4 && tcp && tcp.dst==22' allow

# 2️⃣ Bloquer ICMP
ovn-nbctl acl-add ls-B from-lport 1003 'ip4 && icmp4' drop

# 3️⃣ Tout le reste → DROP
ovn-nbctl acl-add ls-B from-lport 0 'ip4' drop
ovn-nbctl acl-add ls-B to-lport   0 'ip4' drop
```

💡 Notes :

* Les ACLs `from-lport` contrôlent le trafic **émis** par les VMs du switch.
* Les ACLs `to-lport` contrôlent le trafic **reçu** par les VMs du switch.
* Ici, on agit surtout sur `ls-B` → le trafic sortant de `vmB`.

---

# 🧪 5. Tests dans les VMs

### 🧱 5.1 Depuis vmB (client)

#### 🔹 Test ICMP (bloqué)

```bash
ping -c 3 10.0.1.10
```

➡️ Échec (aucune réponse).

#### 🔹 Test SSH (autorisé)

D’abord activer SSH sur vmA :

```bash
# sur vmA
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

Puis depuis vmB :

```bash
ssh ubuntu@10.0.1.10
```

➡️ Fonctionne ✅ (autorisé sur port 22).

#### 🔹 Test HTTP (bloqué)

Sur vmB :

```bash
curl -I http://10.0.1.10
```

➡️ Échec (drop explicite).

---

# 🔍 6. Vérification et audit

### 6.1 Lister les ACLs

```bash
ovn-nbctl acl-list ls-B
```

Exemple :

```
from-lport priority=1003, match=(ip4 && icmp4), action=drop
from-lport priority=1002, match=(ip4 && tcp && tcp.dst==22), action=allow
from-lport priority=0, match=(ip4), action=drop
```

---

### 6.2 Audit avec `ovn-trace`

👉 Depuis le **control node** :

#### 🔸 Simulation d’un ping (bloqué)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && icmp4'
```

💡 Résultat :

```
drop; (ACL drop: priority 1003, match ip4 && icmp4)
```

#### 🔸 Simulation d’un SSH (autorisé)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==22'
```

💡 Résultat :

```
allow; (ACL allow: priority 1002, match ip4 && tcp && tcp.dst==22)
```

#### 🔸 Simulation d’un HTTP (refusé)

```bash
ovn-trace ls-B 'inport=="vmB" && ip4.src==10.0.2.10 && ip4.dst==10.0.1.10 && tcp && tcp.dst==80'
```

💡 Résultat :

```
drop; (ACL drop: priority 0, match ip4)
```

---

# 🧾 7. Logging et audit des ACLs

OVN permet de **loguer les ACLs** pour analyse ou centralisation (via syslog, journald ou Splunk).

👉 Exemple : on ajoute une ACL avec **logging activé** :

```bash
ovn-nbctl acl-add ls-B from-lport 1005 'ip4 && tcp && tcp.dst==443' drop \
  log=true name="drop_https" severity=info
```

Vérification :

```bash
ovn-nbctl acl-list ls-B | grep log
```

Sortie :

```
from-lport priority=1005, match=(ip4 && tcp && tcp.dst==443), action=drop, log:severity=info:name=drop_https
```

🧩 Ces logs apparaissent dans :

```
sudo journalctl -u ovn-controller -f
```

ou dans un pipeline syslog (ex. `/var/log/openvswitch/ovs-vswitchd.log`).

---

# 💡 8. Exercice pratique (à faire en démo)

| Étape | Action                                | Résultat attendu                         |
| ----- | ------------------------------------- | ---------------------------------------- |
| 1     | Appliquer les ACLs ci-dessus sur ls-B | OK                                       |
| 2     | Ping depuis vmB vers vmA              | ❌ Bloqué                                 |
| 3     | SSH depuis vmB vers vmA               | ✅ Autorisé                               |
| 4     | HTTP depuis vmB vers vmA              | ❌ Bloqué                                 |
| 5     | ovn-trace des 3 cas                   | Montrer `allow` / `drop`                 |
| 6     | Supprimer ACL SSH                     | SSH bloqué aussi                         |
| 7     | ovn-appctl recompute                  | Règles OpenFlow recréées automatiquement |

---

# 🧹 9. Nettoyage

```bash
ovn-nbctl acl-del ls-B
ovn-nbctl acl-del ls-A
```

---

# 🧰 Récapitulatif synthétique

| Concept        | Commande / Observation                                        |
| -------------- | ------------------------------------------------------------- |
| Ajouter ACL    | `ovn-nbctl acl-add <ls> from-lport <prio> '<match>' <action>` |
| Supprimer ACL  | `ovn-nbctl acl-del <ls>`                                      |
| Vérifier       | `ovn-nbctl acl-list <ls>`                                     |
| Tester logique | `ovn-trace <ls> '<flux>'`                                     |
| Loguer         | `log=true name="nom" severity=info`                           |
| Audit runtime  | `journalctl -u ovn-controller -f`                             |

---

Souhaites-tu que je t’ajoute la **version "scriptable" (lab complet reproductible)** de cet atelier ACL, avec :

* un script `control-acl-demo.sh` (création + suppression),
* un script `client-test.sh` (tests ping, ssh, curl),
* et un **résumé audit/log** intégré ?

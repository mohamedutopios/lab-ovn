Parfait 🔥 — on reste **dans ton même lab OVN complet** (avec `control`, `compute1`, `compute2`, `vmA`, `vmB`) et on va ajouter **une démonstration pratique QoS** : shaping, policing, burst et priority queue.
C’est une démo idéale pour montrer comment **OVN + OVS permettent de contrôler la bande passante**, exactement comme un routeur professionnel.

---

# 🎯 Objectif de l’atelier

Mettre en place **un goulot d’étranglement contrôlé** entre `vmB` (10.0.2.10) et `vmA` (10.0.1.10), pour illustrer :

| Concept            | Description                                                    |
| ------------------ | -------------------------------------------------------------- |
| **Shaping**        | Contrôle du débit moyen sortant (ex : 1 Mbit/s max).           |
| **Policing**       | Supprime ou droppe les paquets dépassant la limite du burst.   |
| **Burst**          | Quantité temporaire de données autorisée au-delà de la limite. |
| **Priority Queue** | Donne la priorité à certains flux (ex : HTTP > ICMP).          |

---

# 🧱 1. Contexte réseau

| VM              | Réseau logique | IP                  | Localisation |
| --------------- | -------------- | ------------------- | ------------ |
| vmA             | ls-A           | 10.0.1.10           | compute1     |
| vmB             | ls-B           | 10.0.2.10           | compute2     |
| Routeur logique | lr-AB          | 10.0.1.1 / 10.0.2.1 | OVN Central  |

Tout est déjà configuré dans ton lab.

---

# ⚙️ 2. Limitation de bande passante (shaping + policing)

On limite le trafic **sortant de vmB** à **1 Mbit/s** avec un **burst de 200 kbit/s**.

👉 Sur le **control node (192.168.56.10)** :

```bash
# Nettoyer d’éventuelles règles QoS
ovn-nbctl qos-del ls-B

# Ajouter une règle QoS sur le switch logique "ls-B"
ovn-nbctl qos-add ls-B from-lport 1001 \
  'outport == "vmB" && ip4' \
  rate=1000000 burst=200000
```

💡

* `from-lport` → la limitation s’applique en sortie du port logique (`vmB`).
* `rate` → débit moyen max (en bits/s).
* `burst` → tolérance temporaire avant “policing”.

Vérification :

```bash
ovn-nbctl list qos
```

Exemple attendu :

```
_uuid               : 72e1b...
direction           : from-lport
priority            : 1001
match               : outport == "vmB" && ip4
bandwidth           : rate=1000000, burst=200000
```

---

# 🧩 3. Vérification OVS côté compute (plan de données)

👉 Sur **compute2** (où tourne vmB) :

```bash
sudo ovs-vsctl list qos
sudo ovs-vsctl list queue
```

Tu verras :

```
_uuid               : 9f2b...
other_config        : {max-rate="1000000", burst="200000"}
```

---

# 🔝 4. Priority Queue (files de priorité sur vmB)

On crée deux files :

* queue 0 = trafic “normal” (500 Kbit/s max)
* queue 1 = trafic “prioritaire” (1.5 Mbit/s max)

👉 Toujours sur **compute2** :

```bash
sudo ovs-vsctl -- set port vmB qos=@newqos \
  -- --id=@newqos create qos type=linux-htb other-config:max-rate=2000000 queues:0=@q0 queues:1=@q1 \
  -- --id=@q0 create queue other-config:max-rate=500000 other-config:priority=0 \
  -- --id=@q1 create queue other-config:max-rate=1500000 other-config:priority=1
```

Vérifie :

```bash
sudo ovs-vsctl list queue
```

💡 Tu as maintenant deux queues physiques associées au port `vmB` :

* **queue 0** : trafic “lent” (ex. ICMP)
* **queue 1** : trafic “rapide” (ex. HTTP)

---

# 🧪 5. Simulation de goulot d’étranglement

### 🖥️ Sur vmA

Lancer un serveur HTTP :

```bash
sudo python3 -m http.server 80
```

### 💻 Sur vmB

Installer les outils :

```bash
sudo apt update && sudo apt install -y iperf3
```

#### 🔹 Test 1 — sans priorisation

```bash
iperf3 -c 10.0.1.10 -p 80 -t 10
```

👉 Tu verras un débit ≈ **1 Mbit/s**, parfois 1.2 Mbit/s à cause du `burst`.

#### 🔹 Test 2 — avec priorisation (HTTP haute priorité)

Tu peux associer les paquets HTTP à la queue 1 dans une règle QoS OVN :

Sur **control** :

```bash
ovn-nbctl qos-add ls-B from-lport 1002 \
  'outport == "vmB" && ip4 && tcp && tcp.dst == 80' \
  rate=1500000 burst=300000 dscp=10
```

Cette règle mettra automatiquement les paquets HTTP dans la **queue prioritaire**.

#### 🔹 Test 3 — ICMP “non prioritaire”

Sur **vmB** :

```bash
ping -f 10.0.1.10
```

Le ping va ralentir : le flux est dans la **queue 0** (faible priorité).

---

# 🔬 6. Observation et mesure

### Sur **compute2**

Voir le débit réellement transmis :

```bash
sudo ovs-ofctl dump-ports br-int | grep vmB
```

Tu verras les octets/paquets évoluer lentement → ~1 Mbit/s.

### Sur **control**

Inspecter les objets QoS :

```bash
ovn-nbctl list qos
```

### Sur **compute2**

Vérifie la file utilisée :

```bash
sudo ovs-vsctl list queue
```

---

# 📉 7. Visualisation du goulot (optionnel)

Tu peux lancer un `tcpdump` pour observer les bursts :

```bash
sudo tcpdump -i br-int host 10.0.1.10 and tcp port 80 -n
```

Tu verras les paquets arriver de façon irrégulière (petits bursts suivis de pauses).

---

# 🧠 8. Explication simple à montrer en formation

| Concept            | Observation dans le lab                                 |
| ------------------ | ------------------------------------------------------- |
| **Shaping**        | Le débit moyen sortant de vmB plafonne à 1 Mbit/s.      |
| **Burst**          | Petits pics au-delà du plafond (~200 kbit/s).           |
| **Policing**       | Les paquets excédentaires au-delà du burst sont dropés. |
| **Priority Queue** | HTTP passe mieux que ICMP si saturation.                |

---

# 🧹 9. Nettoyage

Sur **control** :

```bash
ovn-nbctl qos-del ls-B
```

Sur **compute2** :

```bash
sudo ovs-vsctl --all destroy qos
sudo ovs-vsctl --all destroy queue
```

---

# 🧰 Résumé des commandes clés

| Étape                   | Commande                                                                                   | Où        |          |
| ----------------------- | ------------------------------------------------------------------------------------------ | --------- | -------- |
| Ajouter QoS (OVN)       | `ovn-nbctl qos-add ls-B from-lport 1001 'outport=="vmB" && ip4' rate=1000000 burst=200000` | control   |          |
| Vérifier QoS OVN        | `ovn-nbctl list qos`                                                                       | control   |          |
| Créer queues (priority) | `ovs-vsctl -- set port vmB qos=@newqos ...`                                                | compute2  |          |
| Vérifier queues         | `ovs-vsctl list queue`                                                                     | compute2  |          |
| Tester débit            | `iperf3 -c 10.0.1.10 -p 80 -t 10`                                                          | vmB       |          |
| Vérifier stats          | `ovs-ofctl dump-ports br-int                                                               | grep vmB` | compute2 |

---

Souhaites-tu que je t’ajoute maintenant une **version scriptée complète** (par rôle : control.sh / compute2.sh / test.sh) que tu pourras rejouer pour chaque démo QoS (avec et sans limitation) ?

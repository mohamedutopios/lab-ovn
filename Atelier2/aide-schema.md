Parfait 👌
Voici maintenant le **schéma complet du routage dans OVN avec Geneve**, que tu peux utiliser pour tes labs, tes cours ou ton diagnostic.
Je te l’explique juste après, ligne par ligne.

---

# 🧭 1. Schéma global : routage avec Geneve dans OVN

```
                 ┌──────────────────────────┐
                 │        OVN Central        │
                 │ ──────────────────────── │
                 │ ovn-northd               │
                 │ ovn-nbdb / ovn-sbdb      │
                 └──────────┬───────────────┘
                            │
             contrôle (TCP 6641/6642)
                            │
    ============================================================
                            │
                (réseau physique / underlay)
                            │
        ┌───────────────────┴────────────────────┐
        │                                        │
┌──────────────────────────┐        ┌──────────────────────────┐
│ Compute Node 1           │        │ Compute Node 2           │
│ IP physique: 192.168.56.11│       │ IP physique: 192.168.56.12│
│ ───────────────────────── │       │ ───────────────────────── │
│ ovs-vswitchd              │       │ ovs-vswitchd              │
│ ovn-controller            │       │ ovn-controller            │
│                          │       │                           │
│   +-------------------+  │       │  +-------------------+     │
│   | br-int (OVS)      |  │       │  | br-int (OVS)      |     │
│   |                   |  │ Geneve │  |                   |     │
│   | VM-A: 10.0.0.10   |<===========>| VM-B: 10.0.1.20   |     │
│   | LS1 (10.0.0.0/24) |  │ tunnel  │  | LS2 (10.0.1.0/24)|     │
│   +--------┬----------+  │ UDP/6081│  +---------┬--------+     │
│            │ LSP1         │       │            │ LSP2          │
│            │               │       │            │               │
│   ┌────────▼──────────┐     │       │  ┌────────▼──────────┐     │
│   │ LR1 logical router│─────┼───────┼──│ LR1 logical router│     │
│   └───────────────────┘     │       │  └───────────────────┘     │
│         DR locale           │       │        DR locale           │
└──────────────────────────┘        └──────────────────────────┘
```

---

# ⚙️ 2. Étapes du flux (VM-A → VM-B)

### 🧩 Étape 1 — émission locale

```
VM-A (10.0.0.10) → 10.0.1.20
```

* Le paquet sort de VM-A et entre dans `br-int` (le switch d’intégration OVS).
* OVN reconnaît que ce flux correspond à un port logique de LS1.

---

### 🧩 Étape 2 — routage logique

* `ovn-controller` applique les **tables OpenFlow** générées par OVN.
* Le flux est redirigé vers le port du **logical router LR1** connecté à LS1.
* Le routeur logique exécute :

  * lookup de la route (10.0.1.0/24 → port LS2)
  * décrément TTL
  * réécriture MAC source/destination

---

### 🧩 Étape 3 — encapsulation Geneve

* OVN identifie que la destination (VM-B) est sur un autre *chassis*.
* Le paquet est encapsulé dans **Geneve (UDP/6081)** :

  * Outer IP src = 192.168.56.11
  * Outer IP dst = 192.168.56.12
  * Geneve header : metadata OVN (datapath ID, logical port IDs…)

---

### 🧩 Étape 4 — transmission inter-chassis

* Le paquet traverse le réseau physique (underlay) entre compute1 et compute2.
* Il n’a plus conscience des adresses 10.0.x.x — seulement du tunnel Geneve.

---

### 🧩 Étape 5 — décapsulation

* Compute2 reçoit le paquet UDP/6081.
* OVS le décode et le remet dans le **datapath logique** de LS2.
* Le paquet est remis à la VM-B sur le bon port logique.

---

### 🧩 Étape 6 — réponse inverse

* Même logique en sens inverse, sans passer par le central.
* C’est **du routage distribué** : chaque hyperviseur gère localement ses routes logiques.

---

# 📦 3. Exemple concret de configuration Geneve

Sur **compute1** :

```bash
sudo ovs-vsctl set open . external-ids:system-id=compute1
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=192.168.56.11
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:192.168.56.10:6642
```

Sur **compute2** :

```bash
sudo ovs-vsctl set open . external-ids:system-id=compute2
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=192.168.56.12
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:192.168.56.10:6642
```

> 🧠 Ces external-ids sont synchronisés dans la Southbound DB d’OVN.
> OVN sait alors construire automatiquement les tunnels Geneve entre les `chassis`.

---

# 🔍 4. Commandes de diagnostic

```bash
# Voir les tunnels Geneve créés
sudo ovs-vsctl list interface | grep -A5 geneve

# Vérifier les chassis connus dans OVN
sudo ovn-sbctl list chassis

# Afficher les routes logiques
sudo ovn-nbctl show

# Voir les flux OpenFlow traduits
sudo ovs-ofctl dump-flows br-int | grep geneve
```

---

# 🧠 5. Résumé visuel du cycle

```
VM-A → LS1 → LR1 → Geneve encapsulation → underlay → Geneve decapsulation → LS2 → VM-B
```

| Étape | Niveau   | Composant    | Action                    |
| ----- | -------- | ------------ | ------------------------- |
| 1     | L2       | LS1          | Bridge logique source     |
| 2     | L3       | LR1          | Routage logique distribué |
| 3     | L3/L2    | OVS / Geneve | Encapsulation             |
| 4     | Physique | Underlay     | Transmission UDP 6081     |
| 5     | L3/L2    | OVS / Geneve | Décapsulation             |
| 6     | L2       | LS2          | Livraison VM destination  |

---

Souhaites-tu que je te montre **le flux Geneve complet analysé avec `ovn-trace`** (simulation d’un ping entre VM-A et VM-B) pour voir la logique OVN détaillée (lookup, routage, tunnel) ?
C’est l’outil le plus puissant pour visualiser le plan de données.

## 🧭 **Programme détaillé — Formation OVN (Open Virtual Network) & OpenFlow**

### Durée : 2 jours (14 heures)

### Public : administrateurs systèmes/réseaux, ingénieurs cloud, DevOps, architectes OpenStack

### Modalité : présentiel ou distanciel avec environnement lab virtualisé (Vagrant, VirtualBox ou KVM)

---

## 🎯 **Objectifs pédagogiques**

À l’issue de la formation, les participants seront capables de :

* Comprendre l’architecture et les composants d’OVN.
* Déployer un environnement OVN autonome (hors OpenStack).
* Gérer et diagnostiquer les flux logiques et physiques via OVN et OpenFlow.
* Implémenter des politiques de sécurité et de QoS réseau.
* Diagnostiquer les problèmes courants et assurer la supervision de l’environnement.

---

## 🧱 **Jour 1 – Architecture OVN & Prise en main**

### **Matin (9h00 – 12h30) : Théorie et fondations**

**1. Introduction générale**

* Virtualisation réseau : OVS, Neutron ML2, OpenFlow, SDN.
* Positionnement d’OVN dans l’écosystème Open vSwitch.
* Rappels sur Neutron et OVS :

* Agents L2, DHCP, L3.
* ML2 mechanism drivers.
* Limitations (latence, debug complexe, dépendance agent).

**2. Présentation d’OVN (Open Virtual Network)**

* Objectifs et philosophie OVN : simplification, automatisation, SDN distribué.
* Composants principaux :

* **Northbound DB** : description logique (intention utilisateur).
* **Southbound DB** : configuration effective (réalité physique).
* **ovn-northd** : moteur de traduction NB → SB.
* **ovn-controller** : agent local d’application.
* Comparaison : OVS vs OVN (routage distribué, absence d’agents Neutron).

**3. Objets logiques d’OVN**

* Logical Switch, Logical Router.
* Ports logiques et bindings.
* Tunnels Geneve / VXLAN.
* ACLs, Load Balancer, DHCP, NAT intégrés.
* Flux de bout en bout : VM1 ↔ Router ↔ VM2.

🧩 **Exercice guidé :**

* Cartographier un flux logique complet dans un diagramme OVN (avec LS, LR, ACLs, NAT).

---

### **Après-midi (13h30 – 17h30) : Mise en pratique sur un lab autonome**

**Atelier 1 – Installation et configuration**

* Création du lab :

* 1 VM « control » (northd + NB/SB DBs).
* 2 VMs « compute » (ovn-controller + ovs).
* Configuration des bridges :

* br-int, br-ex, br-local.
* Association des interfaces physiques et virtuelles.
* Lancement des services :

* `ovn-northd`, `ovsdb-server`, `ovn-controller`.

**Atelier 2 – Manipulation avec les outils OVN**

* Commandes principales :

* `ovn-nbctl show` / `ovn-sbctl show`.
* `ovn-nbctl ls-add`, `lr-add`, `lsp-add`, `lrp-add`.
* Création manuelle d’un réseau logique :

* 2 Logical Switches + 1 Logical Router.
* Connexion des ports logiques (VMs simulées).
* Attribution d’adresses IP et configuration DHCP.
* Ajout de règles ACL (ping, HTTP).
* Mise en place d’un NAT source/destination.

**Atelier 3 – Analyse des flux**

* Utilisation de `ovn-trace` :

* Simulation d’un ping ou d’un flux TCP.
* Analyse de la décision logique (allow/deny).
* Exemples d’échecs : mauvaise ACL, NAT manquant.
* Introduction à `ovn-appctl` pour inspection locale.

---

## ⚙️ **Jour 2 – OpenFlow, QoS, Sécurité et Troubleshooting**

### **Matin (9h00 – 12h30) : OpenFlow et contrôle des flux**

**1. OpenFlow dans OVN**

* Rappel : OpenFlow et rôle dans SDN.
* Comment OVN génère automatiquement des tables OpenFlow.
* Lecture des tables avec `ovs-ofctl dump-flows br-int`.
* Interprétation des champs : priority, match, actions.
* Interaction entre flux logiques OVN et règles physiques OpenFlow.

🧩 **Exercice pratique :**

* Analyse de la table OpenFlow d’un br-int et corrélation avec les objets logiques (LS/LR).
* Supprimer une règle et observer la perte de connectivité.

**2. QoS et gestion de bande passante**

* Concepts : shaping, policing, burst, priority queue.
* Configuration OVN :

* Ajout d’une règle QoS sur un Logical Switch Port.
* Limitation de bande passante sortante.
* Vérification via `ovs-vsctl list queue`.
* Simulation : création d’un goulot d’étranglement contrôlé entre deux VMs.

**3. Sécurité et isolation**

* ACLs : format, sens, priorités, actions.
* Application avec `ovn-nbctl acl-add`.
* Tests :

* Bloquer ICMP.
* Autoriser SSH uniquement.
* Refuser tout le reste.
* Logs et audit d’ACL.

---

### **Après-midi (13h30 – 17h30) : Debugging et bonnes pratiques**

**1. Diagnostic réseau OVN**

* Outils :

* `ovn-trace`, `ovn-sbctl lflow-list`.
* `ovn-appctl ofctrl/dump-flows`.
* `ovs-ofctl dump-ports br-int`.
* `journalctl -u ovn-*`.
* Étapes de résolution :

1. Vérifier NB/SB DBs.
2. Vérifier br-int/br-ex.
3. Vérifier tunnels Geneve.
4. Vérifier règles ACL / NAT.

**2. Études de cas concrets**

* **Cas 1 :** perte de connectivité inter-VM (LR manquant).
* **Cas 2 :** ACL erronée (deny all).
* **Cas 3 :** NAT SNAT non fonctionnel (erreur mapping).
* **Cas 4 :** désynchronisation ovn-controller ↔ southbound DB.

Chaque cas est reproduit et résolu par les stagiaires.

**3. Supervision et maintenance**

* Surveiller OVN :

* Intégration avec Prometheus (OVN Exporter).
* KPIs réseau (latence, packets dropped).
* Logs à surveiller :

* `/var/log/openvswitch/ovs-vswitchd.log`.
* `/var/log/openvswitch/ovn-controller.log`.
* Bonnes pratiques :

* Sauvegarde régulière des DB NB/SB (`ovsdb-client dump`).
* Vérification cohérence (`ovn-sbctl chassis-list`).
* Politique de nommage claire.

**4. Conclusion et évaluation**

* Synthèse des concepts clés.
* Questions/réponses.
* Évaluation pratique : créer un réseau complet avec ACL et NAT, et diagnostiquer une panne simulée.

---

## 🧩 **Supports et environnement fournis**

* Lab virtuel (Vagrant + Ubuntu 24.04) avec OVN 23.x / OVS 3.x.
* Fiches commandes (`ovn-nbctl`, `ovn-sbctl`, `ovn-trace`, `ovs-ofctl`).
* Schémas d’architecture OVN.
* Scénarios de troubleshooting.
* Guide de déploiement autonome OVN (hors OpenStack).
* Option : module complémentaire “Intégration OVN avec OpenStack Neutron”.

---

## 📘 **Évaluation finale**

* QCM de validation (20 questions).
* Étude de cas pratique : résolution d’un incident réseau OVN complet.

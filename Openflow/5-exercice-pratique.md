Excellente question 👌 — tu as parfaitement raison de la poser, car dans un **lab OVN distribué** (avec `control`, `compute1`, `compute2`), **il faut bien distinguer les rôles** :
👉 **certaines métriques viennent du control plane (OVN Central)**
👉 d’autres du data plane (chaque compute, via OVS / ovn-controller).

On va donc clarifier **précisément qui fait quoi**, machine par machine, pour ton cas.

---

# 🧭 **Répartition claire : supervision OVN dans ton lab**

| Rôle         | Machine         | Contient quoi                                     | Supervision à installer ?                 | Pourquoi                               |
| ------------ | --------------- | ------------------------------------------------- | ----------------------------------------- | -------------------------------------- |
| **Control**  | `192.168.56.10` | OVN Central : `ovn-northd`, `NBDB/SBDB`           | ✅ **OVN Exporter + Prometheus + Grafana** | Collecte globale des KPIs réseau       |
| **Compute1** | `192.168.56.11` | `ovn-controller`, `ovs-vswitchd`, `br-int`, `vmA` | ✅ **Node Exporter** *(optionnel)*         | KPIs CPU, mémoire, paquets OVS, br-int |
| **Compute2** | `192.168.56.12` | `ovn-controller`, `ovs-vswitchd`, `br-int`, `vmB` | ✅ **Node Exporter** *(optionnel)*         | KPIs du datapath, latence, drops       |

---

# 🧱 1. Sur **control (192.168.56.10)** — 🧠 *plan de contrôle et supervision centrale*

C’est **ici que tout le monitoring est centralisé**.
Tu vas y installer :

* `ovn-exporter` → expose les métriques OVN NBDB/SBDB.
* `prometheus` → collecte toutes les métriques (OVN + nodes).
* `grafana` → affiche les tableaux de bord.

---

## ⚙️ Étapes sur `control`

### 1️⃣ Installer Prometheus et Grafana

```bash
sudo apt update
sudo apt install -y prometheus grafana
sudo systemctl enable --now prometheus grafana-server
```

### 2️⃣ Installer OVN Exporter (rattaché aux DB locales)

```bash
sudo apt install -y golang-go git make
cd /opt
sudo git clone https://github.com/greenstatic/ovn-exporter.git
cd ovn-exporter && sudo make build

sudo useradd -r -s /bin/false ovn-exporter
sudo tee /etc/systemd/system/ovn-exporter.service >/dev/null <<'EOF'
[Unit]
Description=OVN Exporter for Prometheus
After=network.target

[Service]
User=ovn-exporter
ExecStart=/opt/ovn-exporter/ovn-exporter \
  --listen-address=":9476" \
  --sb-address="tcp:127.0.0.1:6642" \
  --nb-address="tcp:127.0.0.1:6641"

Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ovn-exporter
```

### 3️⃣ Configurer Prometheus pour scrapper OVN Exporter

Édite `/etc/prometheus/prometheus.yml` :

```yaml
scrape_configs:
  - job_name: 'ovn'
    static_configs:
      - targets: ['127.0.0.1:9476']
```

Vérifie :

```bash
curl http://127.0.0.1:9476/metrics | head
sudo systemctl restart prometheus
```

---

# 🖥️ 2. Sur **compute1 et compute2** — ⚙️ *plan de données*

Les computes ne contiennent **pas les bases OVN** (NBDB/SBDB),
mais exécutent **OVS et ovn-controller**, donc tu peux y exporter :

* les **statistiques OVS** (`br-int`, `genev_sys_6081`, etc.)
* les **compteurs de ports** (packets, drops, errors, bytes)
* et les métriques système (CPU, mémoire, I/O) via **Node Exporter**

---

## ⚙️ Étapes sur chaque compute (192.168.56.11 et .12)

### 1️⃣ Installer Node Exporter

```bash
cd /opt
sudo wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
sudo tar xzf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/

sudo useradd -rs /bin/false nodeusr
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=nodeusr
ExecStart=/usr/local/bin/node_exporter --web.listen-address=":9100"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

Vérifie :

```bash
curl http://127.0.0.1:9100/metrics | head
```

---

### 2️⃣ (Optionnel) Ajouter un petit script OVS exporter

Créer `/usr/local/bin/ovs-exporter.sh` :

```bash
#!/bin/bash
echo "# HELP ovs_interface_rx_packets RX packets per interface"
echo "# TYPE ovs_interface_rx_packets counter"
sudo ovs-vsctl --columns=name,statistics list interface | grep -E 'name|rx_packets' | paste - - | awk '{print "ovs_interface_rx_packets{name=\"" $2 "\"} " $4}'
```

Le rendre exécutable :

```bash
sudo chmod +x /usr/local/bin/ovs-exporter.sh
```

Tu peux ensuite l’exposer à Prometheus via un petit endpoint textfile exporter.

---

## 3️⃣ Sur **control**, ajouter les 2 computes dans Prometheus

Modifie `/etc/prometheus/prometheus.yml` :

```yaml
scrape_configs:
  - job_name: 'ovn'
    static_configs:
      - targets: ['127.0.0.1:9476']

  - job_name: 'nodes'
    static_configs:
      - targets: ['192.168.56.11:9100', '192.168.56.12:9100']
```

Redémarre Prometheus :

```bash
sudo systemctl restart prometheus
```

---

# 📈 3. Vérification depuis Grafana

Accède à Grafana :

```
http://192.168.56.10:3000
```

Login : `admin / admin`

Ajoute la **source de données** :

* Type : Prometheus
* URL : `http://localhost:9090`

Importe un dashboard :
👉 `https://grafana.com/grafana/dashboards/16731-ovn-overview/`

Tu verras :

* Nombre de flows installés sur `br-int`
* Nombre de paquets dropés (ACLs, NAT)
* Tunnels Geneve UP/DOWN
* SBDB sync delay
* CPU/memory des computes

---

# 📊 4. KPIs à suivre

| Catégorie            | Métrique Prometheus                                    | Description                         |
| -------------------- | ------------------------------------------------------ | ----------------------------------- |
| **Plan de contrôle** | `ovn_controller_flows_total`                           | Nombre de règles OpenFlow actives   |
| **Synchronisation**  | `ovn_sb_sync_lag_seconds`                              | Retard entre SBDB et ovn-controller |
| **ACLs**             | `ovn_acl_packets_dropped_total`                        | Nombre de paquets rejetés           |
| **Tunnels**          | `ovn_tunnel_up`                                        | État des tunnels Geneve             |
| **Flux / latence**   | `ovn_flow_processing_latency_seconds`                  | Temps moyen de traitement           |
| **Ports OVS**        | `ovs_interface_rx_packets`, `ovs_interface_tx_packets` | Statistiques br-int / vnetX         |
| **Compute health**   | `node_memory_Active_bytes`, `node_cpu_seconds_total`   | Ressources système                  |

---

# 🧠 5. En résumé (où installer quoi)

| Rôle         | Machine       | À installer                              | Ports exposés    | Données collectées               |
| ------------ | ------------- | ---------------------------------------- | ---------------- | -------------------------------- |
| **Control**  | 192.168.56.10 | OVN Exporter + Prometheus + Grafana      | 9476, 9090, 3000 | Flows, ACL, NAT, tunnel, latency |
| **Compute1** | 192.168.56.11 | Node Exporter (+ OVS exporter optionnel) | 9100             | CPU, mémoire, packets, drops     |
| **Compute2** | 192.168.56.12 | Node Exporter (+ OVS exporter optionnel) | 9100             | CPU, mémoire, packets, drops     |

---

Souhaites-tu que je t’envoie maintenant un **fichier `docker-compose.yml` complet** qui déploie automatiquement sur `control` :

* Prometheus
* Grafana
* OVN Exporter
  avec les jobs préconfigurés pour `compute1` et `compute2` ?
  Ce serait la version **clé-en-main et portable** de cette supervision.

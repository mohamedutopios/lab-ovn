Parfait — **uniquement ce qu’il faut pour les ACL**, en gardant **vmA = serveur HTTP (10.0.1.10)** et **vmB = client (10.0.2.10)**, sur ta topo déjà en place (**ls-A**, **ls-B**, **lr-AB**, ports **vmA** et **vmB**).

# Où lancer les commandes ?

👉 **Uniquement sur `control` (192.168.56.10)** avec `ovn-nbctl`.
Aucune commande à changer sur les computes/VMs.

---

# ACL minimales (ICMP + HTTP vmB→vmA, tout le reste bloqué)

> On autorise **ARP** et le **trafic établi/relatif** sur chaque switch logique,
> puis on permet depuis **vmB** : **ICMP echo-request** et **HTTP (TCP/80)** vers **vmA**,
> et on **drop** le reste.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Configuration ACLs - ICMP + HTTP uniquement..."

# Réinitialisation
sudo ovn-nbctl acl-del ls-A || true
sudo ovn-nbctl acl-del ls-B || true

# ============================
# 1️⃣ Règles de base (ARP + connexions établies)
# ============================
for LS in ls-A ls-B; do
  # ARP obligatoire
  sudo ovn-nbctl acl-add $LS from-lport 1001 'arp' allow
  sudo ovn-nbctl acl-add $LS to-lport   1001 'arp' allow
  
  # Connexions établies/reliées (permet les réponses automatiquement)
  sudo ovn-nbctl acl-add $LS from-lport 1000 'ct.est || ct.rel' allow
  sudo ovn-nbctl acl-add $LS to-lport   1000 'ct.est || ct.rel' allow
done

# ============================
# 2️⃣ ICMP (ping) - bidirectionnel
# ============================
for LS in ls-A ls-B; do
  # Sortie : autoriser tout ICMP
  sudo ovn-nbctl acl-add $LS from-lport 900 'ip4 && icmp4' allow-related
  
  # Entrée : autoriser tout ICMP
  sudo ovn-nbctl acl-add $LS to-lport 900 'ip4 && icmp4' allow-related
done

# ============================
# 3️⃣ HTTP (TCP port 80) - bidirectionnel
# ============================
for LS in ls-A ls-B; do
  # Sortie : autoriser connexions HTTP sortantes
  sudo ovn-nbctl acl-add $LS from-lport 800 'ip4 && tcp && tcp.dst==80' allow-related
  
  # Entrée : autoriser connexions HTTP entrantes (serveur)
  sudo ovn-nbctl acl-add $LS to-lport 800 'ip4 && tcp && tcp.dst==80' allow-related
done

# ============================
# 4️⃣ DROP tout le reste
# ============================
for LS in ls-A ls-B; do
  sudo ovn-nbctl acl-add $LS from-lport 0 'ip' drop
  sudo ovn-nbctl acl-add $LS to-lport   0 'ip' drop
done

echo "[OK] ACLs appliquées : ICMP + HTTP autorisés ✅"
echo ""
echo "Tests disponibles :"
echo "  - ping 10.0.1.10  (depuis vmB)"
echo "  - ping 10.0.2.10  (depuis vmA)"
echo "  - curl http://10.0.1.10  (si serveur HTTP sur vmA)"
echo ""
echo "Vérification des ACLs :"
sudo ovn-nbctl list ACL | grep -E 'match|action|priority'
```

---

# Tests rapides

1. **Dans vmA** (serveur HTTP) :

```bash
# vmA (10.0.1.10)
sudo python3 -m http.server 80
```

2. **Dans vmB** (client) :

```bash
# vmB (10.0.2.10) -> ICMP autorisé
ping -c 3 10.0.1.10

# HTTP autorisé
curl -I http://10.0.1.10

# HTTPS/443 non autorisé (doit échouer)
curl -I https://10.0.1.10 || echo "Bloqué (attendu)"
```

> Si quelque chose bloque : vérifie que **vmA** et **vmB** sont bien `up=true` côté OVN :

```bash
ovn-nbctl get logical_switch_port vmA up
ovn-nbctl get logical_switch_port vmB up
```

---

## Variante (si tu préfères cibler par nom de port plutôt que par IP)

```bash
# HTTP depuis vmB vers vmA en utilisant outport
ovn-nbctl acl-add ls-B from-lport 1004 'ip4 && tcp && tcp.dst==80 && outport=="vmA"' allow
# ICMP echo-request depuis vmB vers vmA
ovn-nbctl acl-add ls-B from-lport 1003 'ip4 && icmp4 && icmp4.type==8 && outport=="vmA"' allow
```

Ça suffit pour ta démo **IP statiques + ACL (ICMP/HTTP)**, sans toucher au reste de ta config.



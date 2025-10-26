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

echo "[INFO] Réinitialisation des ACL..."
ovn-nbctl acl-del ls-A || true
ovn-nbctl acl-del ls-B || true

# ============================
# 1️⃣ Règles communes (ARP + flux suivis)
# ============================
for LS in ls-A ls-B; do
  ovn-nbctl acl-add $LS from-lport 1001 'arp' allow
  ovn-nbctl acl-add $LS to-lport   1001 'arp' allow
  ovn-nbctl acl-add $LS from-lport 1000 'ct.est || ct.rel' allow
  ovn-nbctl acl-add $LS to-lport   1000 'ct.est || ct.rel' allow
done

# ============================
# 2️⃣ Flux vmB (10.0.2.10) → vmA (10.0.1.10)
# ============================

# a) Sortant (vmB initie)
ovn-nbctl acl-add ls-B from-lport 1003 'ip4 && icmp4 && icmp4.type==8 && ip4.dst==10.0.1.10' allow  # ping
ovn-nbctl acl-add ls-B from-lport 1004 'ip4 && tcp && tcp.dst==80 && ip4.dst==10.0.1.10' allow       # HTTP

# b) Vers le routeur (ls-B → lr-AB)
ovn-nbctl acl-add ls-B to-lport 1002 'ip4 && (icmp4 || tcp)' allow

# ============================
# 3️⃣ Flux retour vmA → vmB (echo-reply / HTTP response)
# ============================

# a) Autoriser la réponse ICMP type=0 depuis vmA
ovn-nbctl acl-add ls-A from-lport 1003 'ip4 && icmp4 && icmp4.type==0 && ip4.dst==10.0.2.10' allow

# b) Autoriser HTTP réponse (tcp.src==80)
ovn-nbctl acl-add ls-A from-lport 1004 'ip4 && tcp && tcp.src==80 && ip4.dst==10.0.2.10' allow

# c) Autoriser réception côté vmA
ovn-nbctl acl-add ls-A to-lport 1003 'ip4 && icmp4 && icmp4.type==8 && ip4.dst==10.0.1.10' allow
ovn-nbctl acl-add ls-A to-lport 1004 'ip4 && tcp && tcp.dst==80 && ip4.dst==10.0.1.10' allow

# d) Autoriser passage via le routeur côté A
ovn-nbctl acl-add ls-A to-lport 1002 'ip4 && (icmp4 || tcp)' allow

# ============================
# 4️⃣ Politique par défaut : DROP
# ============================
for LS in ls-A ls-B; do
  ovn-nbctl acl-add $LS from-lport 0 'ip' drop
  ovn-nbctl acl-add $LS to-lport   0 'ip' drop
done

echo "[OK] ACLs appliquées avec succès ✅"
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

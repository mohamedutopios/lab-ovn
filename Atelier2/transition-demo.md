Excellente question 👌 — et c’est **exactement** ce qu’il faut bien comprendre pour basculer entre les trois démos **sans tout casser** ton environnement OVN.

👉 L’idée est simple :
on **garde l’infrastructure OVN** (control + computes, topologie logique, liaisons Geneve, etc.)
et on **recrée uniquement les VMs et leurs ports logiques** pour chaque démo.

---

# 🧩 Vue d’ensemble

| Ce qu’on garde                                  | Ce qu’on recrée                                                  |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| OVN Central (`ovn-northd`, NB/SB DBs)           | Les VMs (`vmA`, `vmB`)                                           |
| Topologie OVN (ls-A, ls-B, lr-AB)               | Les ports logiques OVN (`vmA`, `vmB`)                            |
| Réseau libvirt `ovn.xml`                        | Les disques `vmA.img`, `vmB.img` (optionnel)                     |
| OVS sur compute1/2 (`br-int`, `ovn-controller`) | Les fichiers cloud-init (`user-data`, `meta-data`, `*-seed.iso`) |

---

# 🧭 Étapes de transition entre les démos

## ⚙️ 1️⃣ Entre **Demo 1 → Demo 2**

Tu passes d’un lab sans IP à un lab avec IP statique.

### Ce qu’il faut **supprimer / réinitialiser**

Sur chaque compute :

```bash
sudo virsh destroy vmA || true
sudo virsh undefine vmA || true
sudo rm -f /var/lib/libvirt/images/vmA-seed.iso /var/lib/libvirt/images/user-data /var/lib/libvirt/images/meta-data
```

(sur compute2 idem pour vmB)

> 💡 Tu peux **garder** `vmA.img` et `vmB.img` si tu veux gagner du temps —
> mais si tu veux un démarrage « neuf », supprime-les aussi :
>
> ```bash
> sudo rm -f /var/lib/libvirt/images/vmA.img
> sudo cp /var/lib/libvirt/images/jammy.img /var/lib/libvirt/images/vmA.img
> ```

### Ce qu’il faut **garder**

* `br-int` sur chaque compute
* `ovn-controller` actif
* le réseau `ovn` défini dans libvirt
* la topologie OVN sur le control

### Ce qu’il faut **refaire**

* Nouveau `user-data` (avec IP statique)
* Nouveau `meta-data`
* Nouveau `*-seed.iso`
* Nouvelle VM avec `virt-install`
* Nouveau binding `ovs-vsctl set Interface vnetX external-ids:iface-id=vmA`

---

## ⚙️ 2️⃣ Entre **Demo 2 → Demo 3**

Tu passes d’un lab avec IP statique à un lab avec DHCP OVN.

### Ce qu’il faut **supprimer / réinitialiser**

Sur `control` :

```bash
sudo ovn-nbctl lsp-del vmA
sudo ovn-nbctl lsp-del vmB
sudo ovn-nbctl destroy DHCP_Options --all
```

Sur chaque compute :

```bash
sudo virsh destroy vmA || true
sudo virsh undefine vmA || true
sudo rm -f /var/lib/libvirt/images/vmA-seed.iso /var/lib/libvirt/images/user-data /var/lib/libvirt/images/meta-data
```

(sur compute2 idem pour vmB)

### Ce qu’il faut **garder**

* Topologie OVN (ls-A, ls-B, lr-AB)
* Bridge `br-int`
* Réseau `ovn.xml` libvirt
* Images `vmA.img` / `vmB.img` si tu veux gagner du temps

### Ce qu’il faut **refaire**

* Nouveau `user-data` (sans IP statique, DHCP activé)
* Nouveau `meta-data`
* Nouveau `*-seed.iso`
* Redéfinir les ports logiques OVN :

  ```bash
  sudo ovn-nbctl lsp-add ls-A vmA
  sudo ovn-nbctl lsp-add ls-B vmB
  ```
* Relancer les VMs
* Ajouter les DHCP_Options sur `control` :

  ```bash
  UUID_A=$(sudo ovn-nbctl create DHCP_Options cidr=10.0.1.0/24 options="...")
  UUID_B=$(sudo ovn-nbctl create DHCP_Options cidr=10.0.2.0/24 options="...")
  sudo ovn-nbctl lsp-set-addresses vmA "dynamic"
  sudo ovn-nbctl lsp-set-dhcpv4-options vmA $UUID_A
  sudo ovn-nbctl lsp-set-addresses vmB "dynamic"
  sudo ovn-nbctl lsp-set-dhcpv4-options vmB $UUID_B
  ```

---

## ⚙️ 3️⃣ Si tu veux tout réinitialiser complètement

Tu peux nettoyer tout OVN et repartir d’un environnement vierge :

```bash
sudo ovn-nbctl --db=tcp:127.0.0.1:6641 ls-del ls-A
sudo ovn-nbctl --db=tcp:127.0.0.1:6641 ls-del ls-B
sudo ovn-nbctl --db=tcp:127.0.0.1:6641 lr-del lr-AB
sudo ovn-nbctl --db=tcp:127.0.0.1:6641 destroy DHCP_Options --all
```

Puis relancer les étapes de topologie (section 4 du script d’origine).

---

# 🧠 Bon résumé visuel

| Passage    | À supprimer                       | À garder         | À recréer                       |
| ---------- | --------------------------------- | ---------------- | ------------------------------- |
| Demo 1 → 2 | VMs (`virsh undefine`) + seed ISO | OVN infra        | user/meta-data + virt-install   |
| Demo 2 → 3 | VMs + ports LSP + DHCP_Options    | LS/LR OVN        | user/meta-data + DHCP OVN + LSP |
| Full reset | Tout sauf paquets installés       | OVS/OVN services | Topologie + VMs                 |

---

Souhaites-tu que je te crée un **script `cleanup-demo.sh`** qui automatise ce reset entre les démos (avec options `--to-demo2`, `--to-demo3`, `--full` par ex.) ?
Cela t’éviterait les commandes manuelles.

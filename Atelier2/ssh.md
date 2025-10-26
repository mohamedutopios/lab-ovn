C’est un **exemple/placeholder** 👇
`ssh-ed25519 AAAA...TA_CLE_PUBLIQUE...` doit être remplacé par **ta vraie clé publique SSH** (la ligne entière qui se termine souvent par ton login/hostname).

## Où la trouver ?

* **Si tu as déjà une clé** sur la machine depuis laquelle tu te connecteras :

  * Linux/macOS:

    ```bash
    cat ~/.ssh/id_ed25519.pub
    ```
  * Windows (PowerShell):

    ```powershell
    type $env:USERPROFILE\.ssh\id_ed25519.pub
    ```

  Copie **toute** la ligne (elle commence par `ssh-ed25519` et contient une longue chaîne).

* **Si tu n’as pas encore de clé**, génère-en une (recommandé: ed25519) :

  * Linux/macOS/WSL/Windows (Git Bash ou PowerShell avec OpenSSH) :

    ```bash
    ssh-keygen -t ed25519 -C "vm-access" -f ~/.ssh/id_ed25519 -N ""
    cat ~/.ssh/id_ed25519.pub
    ```

  👉 Copie la sortie.

> Tu peux aussi générer la clé **directement sur `compute2`** si tu comptes te connecter à `vmB` depuis `compute2` :
>
> ```bash
> ssh-keygen -t ed25519 -C "vmB-access" -f ~/.ssh/id_ed25519 -N ""
> cat ~/.ssh/id_ed25519.pub
> ```

## Où la mettre dans `user-data` ?

Remplace la ligne placeholder par **ta vraie clé** :

```yaml
#cloud-config
hostname: vmB
users:
  - name: ubuntu
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...ta_vraie_chaine...== vmB-access
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
ssh_pwauth: false
```

Puis régénère l’ISO cloud-init **au bon endroit** et relance si besoin :

```bash
sudo cloud-localds /var/lib/libvirt/images/vmB-seed.iso \
  /var/lib/libvirt/images/user-data-vmB \
  /var/lib/libvirt/images/meta-data-vmB
```

## Astuce (insertion auto sans copier-coller)

Sur `compute2`, si tu viens de générer la clé :

```bash
PUB=$(cat ~/.ssh/id_ed25519.pub)
sudo tee /var/lib/libvirt/images/user-data-vmB >/dev/null <<EOF
#cloud-config
hostname: vmB
users:
  - name: ubuntu
    ssh_authorized_keys:
      - $PUB
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
ssh_pwauth: false
EOF
```

Puis:

```bash
sudo cloud-localds /var/lib/libvirt/images/vmB-seed.iso \
  /var/lib/libvirt/images/user-data-vmB \
  /var/lib/libvirt/images/meta-data-vmB
```

## Alternative sans clé (mot de passe)

Si tu préfères un mot de passe, mets un **hash SHA-512** :

```bash
openssl passwd -6 'TonMotDePasse'
```

et dans `user-data` :

```yaml
users:
  - name: ubuntu
    lock_passwd: false
    passwd: "$6$VRAI_HASH_ICI..."
ssh_pwauth: true
```

Besoin que je t’aide à générer la clé/mettre à jour ton `user-data` actuel ligne par ligne ?

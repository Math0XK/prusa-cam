# prusa-cam

Caméra de surveillance pour imprimante 3D (Prusa MINI) sur **Raspberry Pi 1 B**, qui envoie une photo
toutes les ~10 s à **Prusa Connect**. Visible depuis connect.prusa3d.com ou l'appli Prusa, sur PC
comme sur téléphone, où que tu sois.

Conçu pour un réseau restrictif (eduroam) : tout passe en HTTPS **sortant**, rien n'a besoin
d'être joignable depuis l'extérieur.

```
eduroam (Wi-Fi) ── PC Windows ──(Ethernet, partage ICS)── switch ──┬── Raspberry Pi 1 B + caméra
                                                                   └── Prusa MINI (PrusaLink)
```

## Contenu

| Fichier | Rôle |
|---|---|
| `install.sh` | Installe / met à jour / désinstalle sur le Pi (idempotent) |
| `pi/prusa-cam.sh` | Boucle : photo `rpicam-still` → `PUT` vers Prusa Connect |
| `pi/prusa-cam.service` | Service systemd (démarrage auto, redémarrage en cas de plantage) |
| `pi/prusa-cam.env.example` | Modèle de config, copié vers `/etc/prusa-cam.env` (token, résolution, rotation) |
| `windows/setup-ics.ps1` | Active le partage de connexion Wi-Fi → Ethernet sur le PC, persistant |

Le token Prusa Connect n'est **jamais** dans le dépôt : il vit uniquement dans `/etc/prusa-cam.env` sur le Pi.

---

## Déploiement rapide

Prérequis faits une fois : partage de connexion sur le PC, imprimante ajoutée à Prusa Connect,
token caméra récupéré (détails plus bas).

1. Flasher la carte SD avec **Raspberry Pi Imager** : *Raspberry Pi 1*, **Raspberry Pi OS Lite (32-bit)**,
   nom d'hôte `prusacam`, ton utilisateur, **SSH activé**, pas de Wi-Fi.
2. Caméra branchée **Pi éteint**, Pi relié au switch, alimentation 5V 2A.
3. Depuis le PC :

   ```powershell
   ssh <utilisateur>@prusacam.local
   ```

4. Sur le Pi :

   ```bash
   sudo apt update && sudo apt install -y git
   git clone https://github.com/Math0XK/prusa-cam.git
   cd prusa-cam && sudo ./install.sh --token <TOKEN_PRUSA_CONNECT>
   ```

C'est tout : l'image apparaît dans Prusa Connect sous quelques dizaines de secondes.

### Mettre à jour

```bash
cd ~/prusa-cam && git pull && sudo ./install.sh
```

La config (`/etc/prusa-cam.env`) est conservée.

### Désinstaller

```bash
sudo ~/prusa-cam/install.sh --uninstall
```

---

## Mise en place détaillée (une seule fois)

### 1. Partage de connexion sur le PC (ICS, pas un pont)

Un pont réseau Wi-Fi ↔ Ethernet ne marche quasiment jamais avec eduroam : la plupart des cartes Wi-Fi
ne relaient pas les adresses MAC des autres appareils, et eduroam exige une authentification par appareil.
Le **partage de connexion Internet (ICS)** fait du NAT : vu d'eduroam, il n'y a que ton PC.

Dans un PowerShell **administrateur**, depuis le dossier du dépôt :

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup-ics.ps1
```

Si tes adaptateurs ne s'appellent pas `Wi-Fi` / `Ethernet` (le script liste les noms disponibles en cas d'erreur) :

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup-ics.ps1 -Public "Wi-Fi" -Private "Ethernet 2"
```

L'Ethernet du PC devient `192.168.137.1` et distribue des adresses `192.168.137.x` au switch.
Supprime un éventuel pont réseau existant (`ncpa.cpl`) avant.

Méthode manuelle équivalente : `ncpa.cpl` → clic droit sur **Wi-Fi** → Propriétés → **Partage** →
cocher le partage et choisir l'adaptateur **Ethernet**.

### 2. Prusa MINI

- *Réglages → Réseau → Ethernet* : IP en **DHCP**, noter la nouvelle IP (`192.168.137.x`).
- PrusaLink reste accessible en local sur `http://192.168.137.x`.

### 3. Prusa Connect

1. Sur l'imprimante : *Réglages → Réseau → Prusa Connect → Ajouter l'imprimante*, puis finaliser sur connect.prusa3d.com.
2. Dans Prusa Connect : imprimante → **Caméras** → **Ajouter une nouvelle autre caméra**.
3. Copier le **token** → c'est le `--token` de `install.sh`.

---

## Configuration

`/etc/prusa-cam.env` sur le Pi (puis `sudo systemctl restart prusa-cam`) :

| Variable | Défaut | Description |
|---|---|---|
| `PRUSA_TOKEN` | — | Token de la caméra dans Prusa Connect (obligatoire) |
| `INTERVAL` | `10` | Secondes entre deux photos (Connect n'en accepte pas plus vite) |
| `WIDTH` / `HEIGHT` | `1280` / `720` | Résolution |
| `QUALITY` | `80` | Qualité JPEG |
| `EXTRA_ARGS` | — | Options `rpicam-still` en plus, ex. `--rotation 180` |
| `FINGERPRINT` | dérivé de `/etc/machine-id` | Identifiant unique de la caméra |

## Dépannage

| Symptôme | Piste |
|---|---|
| `prusacam.local` introuvable | `arp -a` sur le PC, chercher une IP en `192.168.137.x` |
| Pas d'Internet sur le Pi / la MINI | Relancer `setup-ics.ps1` (le partage saute parfois quand le Wi-Fi se reconnecte) |
| `Échec de la capture` dans les logs | `rpicam-hello --list-cameras` ; vérifier le sens de la nappe (contacts côté HDMI sur le Pi 1 B) et `camera_auto_detect=1` dans `/boot/firmware/config.txt` |
| `HTTP 401` / `403` | Token invalide ou caméra supprimée dans Connect → `sudo ./install.sh --token <nouveau>` |
| Image floue | L'objectif des caméras v1/v2 se dévisse un peu pour faire le point de près |

Logs : `journalctl -u prusa-cam -f`

## Limites

- Le PC doit rester allumé pendant l'impression (il fait office de routeur).
- Une photo toutes les ~10 s, pas de vidéo en direct.
- Le partage de connexion sur eduroam : vérifie que le règlement de ton établissement le permet.

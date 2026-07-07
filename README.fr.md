# BC-250 Tweaks pour Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Optimisations gaming pour l'**ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) sous **Bazzite Linux**.

Remplacement manuel du patcher image de vietsman, non maintenu pour Bazzite 43+.

---

## Installation rapide (install fraîche)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Cette seule commande installe tout pour un BC-250 neuf : les tweaks système **plus DeckyLoader et nos plugins** ([BC250-Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky), [SkullKey](https://github.com/Necrosiak/SkullKey), [Steamcord](https://github.com/Necrosiak/Steamcord)). Ensuite, lance **`bc250-status`** à tout moment pour un résumé santé d'un coup d'œil (temps, ventilo, VRAM/UMA, RAM, tweaks actifs, Proton-GE, plugins).

Le script clone ce repo dans `/opt/bc250-tweaks` et installe un service systemd qui **se met à jour automatiquement à chaque boot** (git pull + apply).

---

## Ce qui est appliqué

| # | Tweak | Fichier | Description |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` au repos → `throughput-performance-bazzite` en jeu |
| 2 | Variables gaming | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, cache shaders 10 Go |
| 3 | DRI unified heap | `/etc/drirc` | GPU utilise le pool RAM système — évite OOM VRAM sur gros jeux APU |
| 4 | Pipewire latence | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Kargs kernel | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs installés manuellement (absent de l'image Bazzite) |
| 8 | Switch PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Bascule PPD performance↔balanced via busctl au lancement des jeux |
| 9 | HHD | `/etc/hhd/state.yml` | Profil balanced au repos |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (suit PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Overlay léger, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Sharpening adaptatif, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Dernière version GE-Proton installée |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Règle NOPASSWD pour umr (requis par l'onglet CU du plugin BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Règles NOPASSWD pour la persistance CU au boot (tee, chmod, systemctl) |
| 16 | Helper UMA | `/usr/local/bin/bc250-uma-helper` | Helper root (NOPASSWD via `/etc/sudoers.d/bc250-uma`) pour lire/écrire la variable EFI UMA Frame Buffer du BIOS — utilisé par la section VRAM (UMA) du plugin BC250-Toolkit |

### Option de lancement Steam recommandée

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-update

Le service `bc250-tweaks.service` s'exécute à chaque boot :
1. Vérifie le réseau
2. `git pull` depuis ce repo
3. Relance `apply.sh` (idempotent — ne touche qu'aux fichiers différents)

```bash
# Voir les logs
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Forcer une mise à jour maintenant
sudo /opt/bc250-tweaks/update.sh
```

---

## Notes matériel BC-250

- **GPU** : Cyan Skillfish, device ID `731F`, vendor `1002`
- Certains jeux ne reconnaissent pas ce GPU → spoof DXVK : `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP** : ryzenadj et adjustor non supportés sur V2000 (Fam17h model 71)
- **Kernels à éviter** : 6.15.0–6.15.6 et 6.17.8–6.17.10 (driver GPU broken)
- **ReBAR/SAM** : la capacité Resizable BAR existe mais plafonne à 1 Go sur le BC-250 (souvent laissée à 256 Mo) — insuffisant pour les gros jeux DX12. Utiliser l'**UMA Frame Buffer** du BIOS à la place.
- **UE5 DX12 « out of video memory »** : certains jeux Unreal Engine 5 en DX12 crashent à l'init du rendu alors qu'il reste de la VRAM libre. Le unified heap global (tweak #3) aide les jeux DXVK/Vulkan mais masque la VRAM dédiée à VKD3D (DX12). Fix : régler l'**UMA Frame Buffer** du BIOS sur Auto (~8 Go sur une carte 16 Go) et désactiver le unified heap par jeu — le [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) le fait automatiquement via son preset `ue5_dx12_oom`.

---

## Voir aussi

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — base de données de jeux optimisés, applicable depuis Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki communautaire BC-250 Linux
- [bc250.info](https://bc250.info)

---

## 🐧 Compatibilité

Nous faisons le nécessaire pour que ces tweaks fonctionnent sur **tous les systèmes d'exploitation documentés pour le BC-250** ([doc communautaire](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… L'objectif : **détection automatique de l'OS** pour qu'`apply.sh` utilise la bonne méthode (arguments noyau, paquets, services) sur votre distribution.

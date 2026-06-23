# BC-250 Tweaks für Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Gaming-Optimierungen für den **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) unter **Bazzite Linux**.

Manueller Ersatz für vietsmanns Image-Patcher, der für Bazzite 43+ nicht mehr gepflegt wird.

---

## Schnellinstallation (Ersteinrichtung)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Das Skript klont dieses Repository nach `/opt/bc250-tweaks` und installiert einen systemd-Dienst, der **bei jedem Boot automatisch aktualisiert** (git pull + apply).

---

## Angewendete Tweaks

| # | Tweak | Datei | Beschreibung |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` im Ruhezustand → `throughput-performance-bazzite` im Spiel |
| 2 | Gaming-Umgebungsvariablen | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, 10 GB Shader-Cache |
| 3 | DRI Unified Heap | `/etc/drirc` | GPU nutzt System-RAM-Pool — verhindert VRAM OOM bei großen APU-Spielen |
| 4 | Pipewire-Latenz | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl Gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Kernel-Argumente | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=14750`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + Libs manuell installiert (im Bazzite-Basisimage nicht enthalten) |
| 8 | PPD-Schalter | `/usr/local/bin/gamemode-{start,end}.sh` | Schaltet PPD performance↔balanced via busctl beim Spielstart |
| 9 | HHD | `/etc/hhd/state.yml` | balanced-Profil im Ruhezustand |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | `--autopower`-Scheduler (folgt PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Leichtes Overlay, Toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Adaptives Schärfen, Toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Neueste GE-Proton-Version installiert |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | NOPASSWD sudo-Regel für umr (benötigt vom CU-Tab des BC250-Toolkit-Plugins) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | NOPASSWD sudo-Regeln für CU-Boot-Persistenz (tee, chmod, systemctl) |

### Empfohlene Steam-Startoption

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-Update

Der `bc250-tweaks.service` läuft bei jedem Boot:
1. Prüft das Netzwerk
2. `git pull` aus diesem Repository
3. Führt `apply.sh` erneut aus (idempotent — ändert nur geänderte Dateien)

```bash
# Logs anzeigen
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Update jetzt erzwingen
sudo /opt/bc250-tweaks/update.sh
```

---

## BC-250 Hardware-Hinweise

- **GPU**: Cyan Skillfish, Device ID `731F`, Vendor `1002`
- Einige Spiele erkennen diese GPU nicht → DXVK-Spoof: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj und adjustor nicht unterstützt auf V2000 (Fam17h model 71)
- **Zu vermeidende Kernel**: 6.15.0–6.15.6 und 6.17.8–6.17.10 (defekter GPU-Treiber)
- **ReBAR/SAM**: unterstützt

---

## Siehe auch

- [BC250 Toolkit (DeckyLoader-Plugin)](https://github.com/Necrosiak/bc250-toolkit-decky) — Community-Spieldatenbank, Einstellungen direkt aus Steam anwenden
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — BC-250 Linux Community-Wiki
- [bc250.info](https://bc250.info)

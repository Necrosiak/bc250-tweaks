# BC-250 Tweaks for Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Gaming optimizations for the **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) under **Bazzite Linux**.

Manual replacement for vietsman's image patcher, which is no longer maintained for Bazzite 43+.

---

## Quick Install (fresh setup)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

The script clones this repo to `/opt/bc250-tweaks` and installs a systemd service that **auto-updates on every boot** (git pull + apply).

---

## Applied Tweaks

| # | Tweak | File | Description |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` at rest → `throughput-performance-bazzite` in game |
| 2 | Gaming env vars | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, 10 GB shader cache |
| 3 | DRI unified heap | `/etc/drirc` | GPU uses system RAM pool — prevents VRAM OOM on large APU games |
| 4 | Pipewire latency | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Kernel args | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=14750`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs installed manually (absent from Bazzite base image) |
| 8 | PPD switch | `/usr/local/bin/gamemode-{start,end}.sh` | Switches PPD performance↔balanced via busctl on game launch |
| 9 | HHD | `/etc/hhd/state.yml` | balanced profile at rest |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | `--autopower` scheduler (follows PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Lightweight overlay, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Adaptive sharpening, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Latest GE-Proton installed |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | NOPASSWD sudo rule for umr (required by BC250-Toolkit plugin CU tab) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | NOPASSWD sudo rules for CU boot persistence (tee, chmod, systemctl) |

### Recommended Steam launch option

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-update

The `bc250-tweaks.service` runs on every boot:
1. Checks network
2. `git pull` from this repo
3. Reruns `apply.sh` (idempotent — only touches changed files)

```bash
# View logs
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Force update now
sudo /opt/bc250-tweaks/update.sh
```

---

## BC-250 Hardware Notes

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Some games don't recognize this GPU → DXVK spoof: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj and adjustor not supported on V2000 (Fam17h model 71)
- **Kernels to avoid**: 6.15.0–6.15.6 and 6.17.8–6.17.10 (broken GPU driver)
- **ReBAR/SAM**: supported

---

## See Also

- [BC250 Toolkit (DeckyLoader plugin)](https://github.com/Necrosiak/bc250-toolkit-decky) — community game database, apply settings from Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — BC-250 Linux community wiki
- [bc250.info](https://bc250.info)

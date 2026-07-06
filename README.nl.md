# BC-250 Tweaks voor Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Gaming-optimalisaties voor de **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) onder **Bazzite Linux**.

Handmatige vervanging voor de image-patcher van vietsman, die niet meer wordt onderhouden voor Bazzite 43+.

---

## Snelle installatie (nieuw systeem)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Het script kloont deze repo naar `/opt/bc250-tweaks` en installeert een systemd-service die **bij elke boot automatisch bijwerkt** (git pull + apply).

---

## Toegepaste tweaks

| # | Tweak | Bestand | Beschrijving |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` in rust → `throughput-performance-bazzite` in spel |
| 2 | Gaming-omgevingsvariabelen | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, 10 GB shader-cache |
| 3 | DRI unified heap | `/etc/drirc` | GPU gebruikt systeem-RAM-pool — voorkomt VRAM OOM bij grote APU-games |
| 4 | Pipewire-latentie | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Kernel-argumenten | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs handmatig geïnstalleerd (ontbreekt in Bazzite-basisimage) |
| 8 | PPD-schakelaar | `/usr/local/bin/gamemode-{start,end}.sh` | Schakelt PPD performance↔balanced via busctl bij spelstart |
| 9 | HHD | `/etc/hhd/state.yml` | balanced-profiel in rust |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | `--autopower`-scheduler (volgt PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Licht overlay, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Adaptief verscherpen, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Nieuwste GE-Proton geïnstalleerd |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | NOPASSWD sudo-regel voor umr (vereist door CU-tabblad van BC250-Toolkit plugin) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | NOPASSWD sudo-regels voor CU-boot-persistentie (tee, chmod, systemctl) |
| 16 | UMA-helper | `/usr/local/bin/bc250-uma-helper` | Root-helper (NOPASSWD via `/etc/sudoers.d/bc250-uma`) om de BIOS-EFI-variabele UMA Frame Buffer te lezen/schrijven — gebruikt door de sectie VRAM (UMA) van de BC250-Toolkit-plugin |

### Aanbevolen Steam-startoptie

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-update

De `bc250-tweaks.service` draait bij elke boot:
1. Controleert het netwerk
2. `git pull` vanuit dit repo
3. Voert `apply.sh` opnieuw uit (idempotent — raakt alleen gewijzigde bestanden aan)

```bash
# Logs bekijken
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Update nu forceren
sudo /opt/bc250-tweaks/update.sh
```

---

## BC-250 Hardware-opmerkingen

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Sommige games herkennen deze GPU niet → DXVK-spoof: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj en adjustor niet ondersteund op V2000 (Fam17h model 71)
- **Te vermijden kernels**: 6.15.0–6.15.6 en 6.17.8–6.17.10 (defect GPU-stuurprogramma)
- **ReBAR/SAM**: de Resizable BAR-capaciteit is aanwezig maar is op de BC-250 beperkt tot 1 GB (vaak op 256 MB gelaten) — te klein voor grote DX12-titels. Gebruik in plaats daarvan de BIOS-**UMA Frame Buffer**.
- **UE5 DX12 "out of video memory"**: sommige Unreal Engine 5-spellen in DX12 crashen bij het initialiseren van de render terwijl er nog VRAM vrij is. De globale unified heap (tweak #3) helpt DXVK/Vulkan-spellen maar verbergt het toegewijde VRAM voor VKD3D (DX12). Fix: zet de BIOS-**UMA Frame Buffer** op Auto (~8 GB op een 16 GB-bord) en schakel de unified heap per spel uit — de [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) doet dit automatisch via zijn `ue5_dx12_oom`-preset.

---

## Zie ook

- [BC250 Toolkit (DeckyLoader-plugin)](https://github.com/Necrosiak/bc250-toolkit-decky) — community-gamesdatabase, instellingen toepassen vanuit Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — BC-250 Linux community-wiki
- [bc250.info](https://bc250.info)

---

## 🐧 Compatibiliteit

We werken er actief aan dat deze tweaks draaien op **elk besturingssysteem dat voor de BC-250 gedocumenteerd is** ([community-docs](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… Doel: **automatische OS-detectie** zodat `apply.sh` de juiste methode (kernelargumenten, pakketten, services) voor jouw distributie gebruikt.

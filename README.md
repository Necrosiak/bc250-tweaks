# BC-250 Tweaks for Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Gaming optimizations for the **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) under **Bazzite Linux**.

**Bazzite is the primary, fully tested target.** The script also **auto-detects your OS and bootloader** (package manager and kernel-arg method — rpm-ostree, GRUB, Limine, systemd-boot or rEFInd), so it runs best-effort on the other BC-250-documented systems too (SteamOS/HoloISO, CachyOS/Arch, Fedora, Debian…). Support outside Bazzite is validated through community reports — please [open an issue](https://github.com/Necrosiak/bc250-tweaks/issues) if something misbehaves on your distro.

Manual replacement for vietsman's image patcher, which is no longer maintained for Bazzite 43+.

---

## Quick Install (fresh setup)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

This one command installs everything for a fresh BC-250: the system tweaks **plus DeckyLoader and our plugins** ([BC250-Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky), [SkullKey](https://github.com/Necrosiak/SkullKey), [Steamcord](https://github.com/Necrosiak/Steamcord)). Afterwards, run **`bc250-status`** anytime for a one-glance health report (temps, fan, VRAM/UMA, RAM, active tweaks, Proton-GE, plugins).

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
| 6 | Kernel args | auto (rpm-ostree / grubby / GRUB / Limine / systemd-boot / rEFInd) | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs installed manually (absent from Bazzite base image) |
| 8 | PPD switch | `/usr/local/bin/gamemode-{start,end}.sh` | Switches PPD performance↔balanced via busctl on game launch |
| 9 | HHD | `/etc/hhd/state.yml` | balanced profile at rest |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | `--autopower` scheduler (follows PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Lightweight overlay, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Adaptive sharpening, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Latest GE-Proton installed |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | NOPASSWD sudo rule for umr (required by BC250-Toolkit plugin CU tab) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | NOPASSWD sudo rules for CU boot persistence (tee, chmod, systemctl) |
| 16 | UMA helper | `/usr/local/bin/bc250-uma-helper` | Root helper (NOPASSWD via `/etc/sudoers.d/bc250-uma`) to read/write the BIOS UMA Frame Buffer EFI variable — used by the BC250-Toolkit plugin VRAM (UMA) section |

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
- **ReBAR/SAM**: the Resizable BAR capability is present but caps at 1 GB on the BC-250 (often left at 256 MB) — too small for large DX12 titles. Use the BIOS **UMA Frame Buffer** instead.
- **UE5 DX12 "out of video memory"**: some Unreal Engine 5 games in DX12 crash at render init even with VRAM free. The global unified heap (tweak #3) helps DXVK/Vulkan games but hides the dedicated VRAM from VKD3D (DX12). Fix: set the BIOS **UMA Frame Buffer** to Auto (~8 GB on a 16 GB board) and disable the unified heap per-game — the [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) applies this automatically via its `ue5_dx12_oom` preset.

---

## See Also

- [BC250 Toolkit (DeckyLoader plugin)](https://github.com/Necrosiak/bc250-toolkit-decky) — community game database, apply settings from Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — BC-250 Linux community wiki
- [bc250.info](https://bc250.info)

---

## 🐧 Compatibility

We actively work to make these tweaks run on **every operating system documented for the BC-250** ([community docs](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… The goal: **automatic OS detection** so `apply.sh` uses the right method (kernel args, packages, services) for your distro.

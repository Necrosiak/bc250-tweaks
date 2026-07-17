# BC-250 Tweaks per Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Ottimizzazioni gaming per l'**ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) sotto **Bazzite Linux**.

Sostituzione manuale del patcher image di vietsman, non più mantenuto per Bazzite 43+.

---

## Installazione rapida (prima configurazione)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Questo singolo comando installa tutto per un BC-250 nuovo: i tweak di sistema **più DeckyLoader e i nostri plugin** (BC250-Toolkit, SkullKey, Steamcord). Poi esegui **`bc250-status`** quando vuoi per un riepilogo dello stato (temps, ventola, VRAM/UMA, RAM, tweak attivi, Proton-GE, plugin).

Lo script clona questo repo in `/opt/bc250-tweaks` e installa un servizio systemd che **si aggiorna automaticamente ad ogni avvio** (git pull + apply).

---

## Tweaks applicati

| # | Tweak | File | Descrizione |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` a riposo → `throughput-performance-bazzite` in gioco |
| 2 | Variabili gaming | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, cache shader 10 GB |
| 3 | DRI unified heap | `/etc/drirc` | GPU usa il pool RAM di sistema — evita OOM VRAM sui giochi APU grandi |
| 4 | Latenza Pipewire | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Argomenti kernel | auto (rpm-ostree / grubby / GRUB / Limine / systemd-boot / rEFInd) | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs installati manualmente (assenti nell'immagine base Bazzite) |
| 8 | Switch PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Cambia PPD performance↔balanced via busctl all'avvio dei giochi |
| 9 | HHD | `/etc/hhd/state.yml` | Profilo balanced a riposo |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (segue PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Overlay leggero, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Sharpening adattivo, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Ultima versione GE-Proton installata |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Regola NOPASSWD sudo per umr (richiesta dalla scheda CU del plugin BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Regole NOPASSWD sudo per la persistenza CU al boot (tee, chmod, systemctl) |
| 16 | Helper UMA | `/usr/local/bin/bc250-uma-helper` | Helper root (NOPASSWD via `/etc/sudoers.d/bc250-uma`) per leggere/scrivere la variabile EFI UMA Frame Buffer del BIOS — usato dalla sezione VRAM (UMA) del plugin BC250-Toolkit |

### Opzione di avvio Steam consigliata

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-aggiornamento

Il servizio `bc250-tweaks.service` viene eseguito ad ogni avvio:
1. Verifica la rete
2. `git pull` da questo repo
3. Riesegue `apply.sh` (idempotente — tocca solo i file modificati)

```bash
# Visualizza i log
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Forza l'aggiornamento ora
sudo /opt/bc250-tweaks/update.sh
```

---

## Note hardware BC-250

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Alcuni giochi non riconoscono questa GPU → spoof DXVK: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj e adjustor non supportati su V2000 (Fam17h model 71)
- **Kernel da evitare**: 6.15.0–6.15.6 e 6.17.8–6.17.10 (driver GPU non funzionante)
- **ReBAR/SAM**: la capacità Resizable BAR è presente ma si limita a 1 GB sul BC-250 (spesso lasciata a 256 MB) — insufficiente per i giochi DX12 grandi. Usare invece l'**UMA Frame Buffer** del BIOS.
- **UE5 DX12 «out of video memory»**: alcuni giochi Unreal Engine 5 in DX12 vanno in crash all'inizializzazione del render pur con VRAM libera. L'unified heap globale (tweak #3) aiuta i giochi DXVK/Vulkan ma nasconde la VRAM dedicata a VKD3D (DX12). Fix: impostare l'**UMA Frame Buffer** del BIOS su Auto (~8 GB su una scheda da 16 GB) e disattivare l'unified heap per gioco — il [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) lo fa automaticamente tramite il suo preset `ue5_dx12_oom`.

---

## Vedi anche

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — database giochi della community, applica le impostazioni da Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki community BC-250 Linux
- [bc250.info](https://bc250.info)

---

## 🐧 Compatibilità

Lavoriamo attivamente perché questi tweak funzionino su **tutti i sistemi operativi documentati per la BC-250** ([documentazione della comunità](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… L'obiettivo: **rilevamento automatico dell'OS** perché `apply.sh` usi il metodo giusto (argomenti kernel, pacchetti, servizi) sulla tua distribuzione.

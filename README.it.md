# BC-250 Tweaks per Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Ottimizzazioni gaming per l'**ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) sotto **Bazzite Linux**.

Sostituzione manuale del patcher image di vietsman, non più mantenuto per Bazzite 43+.

---

## Installazione rapida (prima configurazione)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

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
| 6 | Argomenti kernel | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=14750`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs installati manualmente (assenti nell'immagine base Bazzite) |
| 8 | Switch PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Cambia PPD performance↔balanced via busctl all'avvio dei giochi |
| 9 | HHD | `/etc/hhd/state.yml` | Profilo balanced a riposo |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (segue PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Overlay leggero, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Sharpening adattivo, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Ultima versione GE-Proton installata |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Regola NOPASSWD sudo per umr (richiesta dalla scheda CU del plugin BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Regole NOPASSWD sudo per la persistenza CU al boot (tee, chmod, systemctl) |

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
- **ReBAR/SAM**: supportato

---

## Vedi anche

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — database giochi della community, applica le impostazioni da Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki community BC-250 Linux
- [bc250.info](https://bc250.info)

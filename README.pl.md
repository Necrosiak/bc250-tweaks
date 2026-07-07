# BC-250 Tweaks dla Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Optymalizacje gaming dla **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) pod **Bazzite Linux**.

Ręczne zastępstwo dla patchera image'u vietsmana, który nie jest już utrzymywany dla Bazzite 43+.

---

## Szybka instalacja (nowa konfiguracja)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

To jedno polecenie instaluje wszystko dla świeżego BC-250: tweaki systemowe **plus DeckyLoader i nasze wtyczki** (BC250-Toolkit, SkullKey, Steamcord). Następnie uruchom **`bc250-status`** w dowolnej chwili, aby zobaczyć podsumowanie stanu (temp., wentylator, VRAM/UMA, RAM, aktywne tweaki, Proton-GE, wtyczki).

Skrypt klonuje to repo do `/opt/bc250-tweaks` i instaluje usługę systemd, która **automatycznie aktualizuje się przy każdym rozruchu** (git pull + apply).

---

## Zastosowane tweaki

| # | Tweak | Plik | Opis |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` w spoczynku → `throughput-performance-bazzite` w grze |
| 2 | Zmienne gaming | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, cache shaderów 10 GB |
| 3 | DRI unified heap | `/etc/drirc` | GPU używa puli RAM systemu — zapobiega OOM VRAM w dużych grach APU |
| 4 | Latencja Pipewire | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Argumenty jądra | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs zainstalowane ręcznie (nieobecne w bazowym obrazie Bazzite) |
| 8 | Przełącznik PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Przełącza PPD performance↔balanced przez busctl przy uruchamianiu gier |
| 9 | HHD | `/etc/hhd/state.yml` | Profil balanced w spoczynku |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (śledzi PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Lekki overlay, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Adaptywne wyostrzanie, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Zainstalowana najnowsza wersja GE-Proton |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Reguła NOPASSWD sudo dla umr (wymagana przez zakładkę CU pluginu BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Reguły NOPASSWD sudo dla trwałości CU przy rozruchu (tee, chmod, systemctl) |
| 16 | Helper UMA | `/usr/local/bin/bc250-uma-helper` | Root-helper (NOPASSWD przez `/etc/sudoers.d/bc250-uma`) do odczytu/zapisu zmiennej EFI UMA Frame Buffer BIOS-u — używany przez sekcję VRAM (UMA) wtyczki BC250-Toolkit |

### Zalecana opcja uruchamiania Steam

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-aktualizacja

Usługa `bc250-tweaks.service` uruchamia się przy każdym rozruchu:
1. Sprawdza sieć
2. `git pull` z tego repo
3. Ponownie uruchamia `apply.sh` (idempotentny — dotyka tylko zmienionych plików)

```bash
# Przeglądaj logi
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Wymuś aktualizację teraz
sudo /opt/bc250-tweaks/update.sh
```

---

## Uwagi dotyczące sprzętu BC-250

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Niektóre gry nie rozpoznają tego GPU → spoof DXVK: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj i adjustor nieobsługiwane na V2000 (Fam17h model 71)
- **Jądra do unikania**: 6.15.0–6.15.6 i 6.17.8–6.17.10 (uszkodzony sterownik GPU)
- **ReBAR/SAM**: funkcja Resizable BAR jest dostępna, ale na BC-250 ograniczona do 1 GB (często pozostawiona na 256 MB) — za mało dla dużych gier DX12. Zamiast tego użyj **UMA Frame Buffer** w BIOS.
- **UE5 DX12 „out of video memory"**: niektóre gry Unreal Engine 5 w DX12 zawieszają się przy inicjalizacji renderowania mimo wolnego VRAM. Globalny unified heap (tweak #3) pomaga grom DXVK/Vulkan, ale ukrywa dedykowany VRAM przed VKD3D (DX12). Rozwiązanie: ustaw **UMA Frame Buffer** w BIOS na Auto (~8 GB na płycie 16 GB) i wyłącz unified heap dla danej gry — [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) robi to automatycznie przez swój preset `ue5_dx12_oom`.

---

## Zobacz również

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — community baza danych gier, stosuj ustawienia ze Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki społeczności BC-250 Linux
- [bc250.info](https://bc250.info)

---

## 🐧 Kompatybilność

Aktywnie pracujemy nad tym, aby te tweaki działały na **każdym systemie operacyjnym udokumentowanym dla BC-250** ([dokumentacja społeczności](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… Cel: **automatyczne wykrywanie systemu**, aby `apply.sh` używał właściwej metody (argumenty jądra, pakiety, usługi) na twojej dystrybucji.

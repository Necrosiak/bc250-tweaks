# BC-250 Tweaks para Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Otimizações gaming para o **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) sob **Bazzite Linux**.

Substituição manual do patcher de imagem do vietsman, que não é mais mantido para Bazzite 43+.

---

## Instalação rápida (configuração nova)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

O script clona este repo em `/opt/bc250-tweaks` e instala um serviço systemd que **se atualiza automaticamente em cada arranque** (git pull + apply).

---

## Tweaks aplicados

| # | Tweak | Ficheiro | Descrição |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` em repouso → `throughput-performance-bazzite` em jogo |
| 2 | Variáveis gaming | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, cache shaders 10 GB |
| 3 | DRI unified heap | `/etc/drirc` | GPU usa o pool de RAM do sistema — evita OOM VRAM em jogos APU grandes |
| 4 | Latência Pipewire | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Argumentos kernel | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=14750`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs instalados manualmente (ausentes na imagem base Bazzite) |
| 8 | Switch PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Alterna PPD performance↔balanced via busctl ao iniciar jogos |
| 9 | HHD | `/etc/hhd/state.yml` | Perfil balanced em repouso |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (segue PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Overlay leve, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Sharpening adaptativo, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Última versão GE-Proton instalada |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Regra NOPASSWD sudo para umr (necessária pelo separador CU do plugin BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Regras NOPASSWD sudo para persistência CU no arranque (tee, chmod, systemctl) |

### Opção de lançamento Steam recomendada

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-atualização

O serviço `bc250-tweaks.service` corre em cada arranque:
1. Verifica a rede
2. `git pull` a partir deste repo
3. Volta a executar `apply.sh` (idempotente — toca apenas nos ficheiros modificados)

```bash
# Ver logs
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Forçar atualização agora
sudo /opt/bc250-tweaks/update.sh
```

---

## Notas de hardware BC-250

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Alguns jogos não reconhecem esta GPU → spoof DXVK: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj e adjustor não suportados no V2000 (Fam17h model 71)
- **Kernels a evitar**: 6.15.0–6.15.6 e 6.17.8–6.17.10 (driver GPU com erros)
- **ReBAR/SAM**: suportado

---

## Ver também

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — base de dados comunitária de jogos, aplicar definições a partir do Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki da comunidade BC-250 Linux
- [bc250.info](https://bc250.info)

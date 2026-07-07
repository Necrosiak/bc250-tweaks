# BC-250 Tweaks para Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Optimizaciones gaming para el **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) bajo **Bazzite Linux**.

Reemplazo manual del patcher de imagen de vietsman, que ya no se mantiene para Bazzite 43+.

---

## Instalación rápida (instalación nueva)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Este único comando instala todo para un BC-250 nuevo: los tweaks del sistema **más DeckyLoader y nuestros plugins** (BC250-Toolkit, SkullKey, Steamcord). Después, ejecuta **`bc250-status`** cuando quieras para un resumen de estado (temps, ventilador, VRAM/UMA, RAM, tweaks activos, Proton-GE, plugins).

El script clona este repo en `/opt/bc250-tweaks` e instala un servicio systemd que **se actualiza automáticamente en cada arranque** (git pull + apply).

---

## Tweaks aplicados

| # | Tweak | Archivo | Descripción |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` en reposo → `throughput-performance-bazzite` en juego |
| 2 | Variables gaming | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, caché shaders 10 GB |
| 3 | DRI unified heap | `/etc/drirc` | GPU usa el pool de RAM del sistema — evita OOM VRAM en juegos grandes de APU |
| 4 | Latencia Pipewire | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Argumentos kernel | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=8000`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Daemon + libs instalados manualmente (ausentes en la imagen base de Bazzite) |
| 8 | Switch PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Cambia PPD performance↔balanced vía busctl al iniciar juegos |
| 9 | HHD | `/etc/hhd/state.yml` | Perfil balanced en reposo |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Scheduler `--autopower` (sigue PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Overlay ligero, toggle Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Sharpening adaptativo, toggle Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Última versión GE-Proton instalada |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Regla NOPASSWD sudo para umr (requerida por la pestaña CU del plugin BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Reglas NOPASSWD sudo para persistencia CU en el arranque (tee, chmod, systemctl) |
| 16 | Helper UMA | `/usr/local/bin/bc250-uma-helper` | Helper root (NOPASSWD vía `/etc/sudoers.d/bc250-uma`) para leer/escribir la variable EFI UMA Frame Buffer del BIOS — usado por la sección VRAM (UMA) del plugin BC250-Toolkit |

### Opción de inicio Steam recomendada

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Auto-actualización

El servicio `bc250-tweaks.service` se ejecuta en cada arranque:
1. Verifica la red
2. `git pull` desde este repo
3. Vuelve a ejecutar `apply.sh` (idempotente — solo toca archivos modificados)

```bash
# Ver logs
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Forzar actualización ahora
sudo /opt/bc250-tweaks/update.sh
```

---

## Notas de hardware BC-250

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Algunos juegos no reconocen esta GPU → spoof DXVK: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj y adjustor no soportados en V2000 (Fam17h model 71)
- **Kernels a evitar**: 6.15.0–6.15.6 y 6.17.8–6.17.10 (driver GPU roto)
- **ReBAR/SAM**: la capacidad Resizable BAR existe pero se limita a 1 GB en el BC-250 (a menudo dejada en 256 MB) — insuficiente para juegos DX12 grandes. Usar el **UMA Frame Buffer** del BIOS en su lugar.
- **UE5 DX12 «out of video memory»**: algunos juegos Unreal Engine 5 en DX12 fallan al inicializar el render aun con VRAM libre. El unified heap global (tweak #3) ayuda a los juegos DXVK/Vulkan pero oculta la VRAM dedicada a VKD3D (DX12). Solución: poner el **UMA Frame Buffer** del BIOS en Auto (~8 GB en una placa de 16 GB) y desactivar el unified heap por juego — el [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) lo hace automáticamente con su preset `ue5_dx12_oom`.

---

## Ver también

- [BC250 Toolkit (plugin DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — base de datos de juegos de la comunidad, aplicar ajustes desde Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — wiki comunitaria BC-250 Linux
- [bc250.info](https://bc250.info)

---

## 🐧 Compatibilidad

Trabajamos activamente para que estos tweaks funcionen en **todos los sistemas operativos documentados para la BC-250** ([documentación comunitaria](https://elektricm.github.io/amd-bc250-docs)) — Bazzite, SteamOS, CachyOS/Arch, Fedora… El objetivo: **detección automática del SO** para que `apply.sh` use el método correcto (argumentos del kernel, paquetes, servicios) en tu distribución.

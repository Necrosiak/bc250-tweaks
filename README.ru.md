# BC-250 Tweaks для Bazzite

> 🌐 [EN](README.md) · [FR](README.fr.md) · [DE](README.de.md) · [ES](README.es.md) · [IT](README.it.md) · [PT](README.pt.md) · [NL](README.nl.md) · [PL](README.pl.md) · [RU](README.ru.md)

Игровые оптимизации для **ASRock BC-250** (AMD Ryzen Embedded V2000 / Cyan Skillfish GPU) под **Bazzite Linux**.

Ручная замена image-патчера vietsman'а, который больше не поддерживается для Bazzite 43+.

---

## Быстрая установка (новая конфигурация)

```bash
curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
```

Скрипт клонирует этот репо в `/opt/bc250-tweaks` и устанавливает службу systemd, которая **автоматически обновляется при каждой загрузке** (git pull + apply).

---

## Применяемые твики

| # | Твик | Файл | Описание |
|---|---|---|---|
| 1 | Tuned/PPD | `/etc/tuned/ppd.conf` | `balanced-bazzite` в покое → `throughput-performance-bazzite` в игре |
| 2 | Игровые переменные | `~/.config/environment.d/gaming.conf` | RADV_DEBUG=nohiz, RADV_PERFTEST, FSR, Anti-lag, кэш шейдеров 10 ГБ |
| 3 | DRI unified heap | `/etc/drirc` | GPU использует пул ОЗУ системы — предотвращает OOM VRAM в больших играх APU |
| 4 | Задержка Pipewire | `~/.config/pipewire/pipewire.conf.d/` | quantum=512, rate=48000 |
| 5 | Sysctl gaming | `/etc/sysctl.d/99-bc250-gaming.conf` | compaction=0, numa_balancing=0, tcp_fastopen |
| 6 | Аргументы ядра | rpm-ostree | `amdgpu.ppfeaturemask=0xffffffff`, `amdgpu.gttsize=14750`, `split_lock_detect=off`, `transparent_hugepage=madvise` |
| 7 | Gamemode | `/usr/local/bin/` | Демон + библиотеки установлены вручную (отсутствуют в базовом образе Bazzite) |
| 8 | Переключатель PPD | `/usr/local/bin/gamemode-{start,end}.sh` | Переключает PPD performance↔balanced через busctl при запуске игр |
| 9 | HHD | `/etc/hhd/state.yml` | Профиль balanced в покое |
| 10 | scx_lavd | `/etc/scx_loader/config.toml` | Планировщик `--autopower` (следует PPD) |
| 11 | MangoHud | `~/.config/MangoHud/MangoHud.conf` | Лёгкий оверлей, переключатель Shift+F12 |
| 12 | vkBasalt CAS | `~/.config/vkBasalt.conf` | Адаптивное повышение чёткости, переключатель Home |
| 13 | Proton-GE | `~/.steam/steam/compatibilitytools.d/` | Установлена последняя версия GE-Proton |
| 14 | umr sudoers | `/etc/sudoers.d/bc250-umr` | Правило NOPASSWD sudo для umr (требуется вкладкой CU плагина BC250-Toolkit) |
| 15 | CU boot sudoers | `/etc/sudoers.d/bc250-cu-boot` | Правила NOPASSWD sudo для сохранения CU при загрузке (tee, chmod, systemctl) |

### Рекомендуемый параметр запуска Steam

```
MANGOHUD=1 MANGOHUD_CONFIG=no_display ENABLE_VKBASALT=1 gamemoderun %command%
```

---

## Авто-обновление

Служба `bc250-tweaks.service` запускается при каждой загрузке:
1. Проверяет сеть
2. `git pull` из этого репо
3. Повторно запускает `apply.sh` (идемпотентный — изменяет только изменённые файлы)

```bash
# Просмотр логов
journalctl -u bc250-tweaks -f
tail -f /var/log/bc250-tweaks.log

# Принудительное обновление сейчас
sudo /opt/bc250-tweaks/update.sh
```

---

## Аппаратные замечания BC-250

- **GPU**: Cyan Skillfish, device ID `731F`, vendor `1002`
- Некоторые игры не распознают этот GPU → spoof DXVK: `DXVK_CONFIG="dxgi.customDeviceId=731F dxgi.customVendorId=1002"`
- **TDP**: ryzenadj и adjustor не поддерживаются на V2000 (Fam17h model 71)
- **Ядра, которых следует избегать**: 6.15.0–6.15.6 и 6.17.8–6.17.10 (неработающий драйвер GPU)
- **ReBAR/SAM**: возможность Resizable BAR присутствует, но на BC-250 ограничена 1 ГБ (часто остаётся на 256 МБ) — мало для крупных игр DX12. Вместо этого используйте **UMA Frame Buffer** в BIOS.
- **UE5 DX12 «out of video memory»**: некоторые игры Unreal Engine 5 в DX12 падают при инициализации рендера даже при свободной VRAM. Глобальный unified heap (твик #3) помогает играм DXVK/Vulkan, но скрывает выделенную VRAM от VKD3D (DX12). Решение: установите **UMA Frame Buffer** в BIOS на Auto (~8 ГБ на плате 16 ГБ) и отключите unified heap для конкретной игры — [BC250 Toolkit](https://github.com/Necrosiak/bc250-toolkit-decky) делает это автоматически через пресет `ue5_dx12_oom`.

---

## Смотрите также

- [BC250 Toolkit (плагин DeckyLoader)](https://github.com/Necrosiak/bc250-toolkit-decky) — общественная база данных игр, применяйте настройки из Steam
- [AMD BC-250 Docs](https://elektricm.github.io/amd-bc250-docs) — вики сообщества BC-250 Linux
- [bc250.info](https://bc250.info)

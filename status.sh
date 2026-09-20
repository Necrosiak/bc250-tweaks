#!/usr/bin/env bash
# BC-250 — résumé « santé » : températures, ventilateur, VRAM/UMA, tweaks
# actifs, RAM, Proton-GE, plugins. Lecture seule, aucun droit root requis.
# Usage : ./status.sh   (ou bc250-status une fois installé par apply.sh)
set -uo pipefail

TARGET_USER="${SUDO_USER:-${USER:-bazzite}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
: "${TARGET_HOME:=$HOME}"

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_bad=$'\e[31m'; c_dim=$'\e[2m'; c_hd=$'\e[1;36m'; c_z=$'\e[0m'
row() { printf "  %-22s %s\n" "$1" "$2"; }
hdr() { printf "\n${c_hd}%s${c_z}\n" "$1"; }

tcolor() { # $1 temp°C
    local t=${1%.*}
    if   [ -z "$t" ]; then printf "%s" "$c_dim"
    elif [ "$t" -gt 90 ]; then printf "%s" "$c_bad"
    elif [ "$t" -gt 75 ]; then printf "%s" "$c_warn"
    else printf "%s" "$c_ok"; fi
}

# ── températures + ventilateur ────────────────────────────────────────────────
cpu_t=""; gpu_t=""; fan=""
for h in /sys/class/hwmon/hwmon*; do
    n=$(cat "$h/name" 2>/dev/null)
    case "$n" in
        k10temp) [ -r "$h/temp1_input" ] && cpu_t=$(( $(cat "$h/temp1_input")/1000 ));;
        amdgpu|gpu_thermal) [ -r "$h/temp1_input" ] && gpu_t=$(( $(cat "$h/temp1_input")/1000 ));;
    esac
    for f in "$h"/fan*_input; do
        [ -r "$f" ] || continue
        r=$(cat "$f" 2>/dev/null); [ "${r:-0}" -gt "${fan:-0}" ] && fan=$r
    done
done

hdr "🌡️  Températures & ventilateur"
row "CPU" "$(tcolor "$cpu_t")${cpu_t:-N/A}°C${c_z}"
row "GPU" "$(tcolor "$gpu_t")${gpu_t:-N/A}°C${c_z}"
row "Ventilateur" "${fan:-N/A} RPM"

# ── VRAM / UMA / RAM ──────────────────────────────────────────────────────────
hdr "🎛️  Mémoire (VRAM / RAM)"
gtt=$(grep -o 'amdgpu\.gttsize=[0-9]*' /proc/cmdline | head -1 | cut -d= -f2)
row "gttsize (karg)" "${gtt:-non défini} Mo"
uma_helper=/usr/local/bin/bc250-uma-helper
uma_var=/sys/firmware/efi/efivars/AmdSetup-3a997502-647a-4c82-998e-52ef9486a247
if [ -x "$uma_helper" ] && sudo -n "$uma_helper" read "$uma_var" >/dev/null 2>&1; then
    fb=$(sudo -n "$uma_helper" read "$uma_var" 2>/dev/null | tail -c+5 | od -An -tu1 -j606 -N1 2>/dev/null | tr -d ' ')
    case "$fb" in 15|"") row "UMA Frame Buffer" "Auto (≈8G)";; *) row "UMA Frame Buffer" "octet=$fb";; esac
else
    row "UMA Frame Buffer" "${c_dim}(helper non lancé / pas de sudo -n)${c_z}"
fi
read -r memt mema < <(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print t" "a}' /proc/meminfo)
if [ -n "${memt:-}" ]; then
    used=$(( (memt-mema)/1024 )); tot=$(( memt/1024 )); pct=$(( (memt-mema)*100/memt ))
    col=$c_ok; [ "$pct" -gt 85 ] && col=$c_bad || { [ "$pct" -gt 70 ] && col=$c_warn; }
    row "RAM (OS)" "${col}${used} / ${tot} Mo (${pct}%)${c_z}"
fi

# ── tweaks actifs ─────────────────────────────────────────────────────────────
hdr "⚙️  Tweaks actifs"
scx=$(cat /sys/kernel/sched_ext/state 2>/dev/null)
scx_s=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || cat /sys/kernel/sched_ext/*/ops 2>/dev/null | head -1)
[ "$scx" = "enabled" ] && row "scheduler scx" "${c_ok}$scx${c_z} ${scx_s:+($scx_s)}" || row "scheduler scx" "${c_dim}${scx:-off}${c_z}"
# Un scheduler scx qui cale fige TOUTE l'interface plusieurs secondes, puis est
# sorti du jeu par le watchdog noyau et relancé : sans cette ligne, le symptôme
# ressemble à un problème de GPU ou de gamescope. Le compteur le nomme.
scx_stalls=$(journalctl -b 0 -k --no-pager 2>/dev/null | grep -c 'runnable task stall')
if [ "${scx_stalls:-0}" -gt 0 ]; then
    row "  ↳ blocages scx" "${c_bad}${scx_stalls} depuis le boot${c_z} ${c_dim}(gels de l'interface — voir configs/scx_loader.toml)${c_z}"
fi
pgrep -x gamemoded >/dev/null 2>&1 && row "gamemoded" "${c_ok}actif${c_z}" || row "gamemoded" "${c_dim}inactif${c_z}"
grep -q "zswap.enabled=1" /proc/cmdline 2>/dev/null && row "zswap" "${c_ok}activé${c_z}" || row "zswap" "${c_dim}off${c_z}"
grep -q "split_lock_detect=off" /proc/cmdline && row "split_lock_detect" "${c_ok}off (bon)${c_z}" || row "split_lock_detect" "${c_dim}on${c_z}"
[ -x /usr/local/bin/gamemoderun ] || command -v gamemoderun >/dev/null 2>&1 && row "gamemode (bin)" "${c_ok}présent${c_z}"

# ── intégrations matérielles optionnelles ─────────────────────────────────────
# Lecture seule : ces états empêchent de proposer une fonction TV/manette/Wi-Fi
# qui n'est pas réellement disponible sur la machine.
hdr "🔌 Intégrations matérielles"

# NetworkManager est la source de vérité pour l'état Wi-Fi. Le lien sysfs
# renseigne le pilote effectif sans supposer une puce AIC/Intel/Realtek.
wifi_dev=""
if command -v nmcli >/dev/null 2>&1; then
    wifi_dev=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }')
fi
if [ -n "$wifi_dev" ]; then
    wifi_state=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$wifi_dev" '$1 == d { print $2; exit }')
    wifi_mod=$(basename "$(readlink -f "/sys/class/net/$wifi_dev/device/driver/module" 2>/dev/null)" 2>/dev/null)
    [ "$wifi_mod" = "module" ] && wifi_mod=""
    row "Wi-Fi" "${c_ok}${wifi_dev}${c_z} · ${wifi_state:-état inconnu}${wifi_mod:+ · $wifi_mod}"
else
    row "Wi-Fi" "${c_dim}aucun adaptateur NetworkManager${c_z}"
fi

# Le module peut être prêt sans manette présente. Les deux états sont affichés.
ds_count=$(grep -Eil 'dualsense|wireless controller|playstation' /sys/class/input/input*/name 2>/dev/null | wc -l | tr -d ' ')
# /proc/modules et PAS `lsmod | grep -q` : ce script tourne sous `set -o
# pipefail`, et grep -q sort dès la première ligne trouvée, ce qui tue lsmod par
# SIGPIPE (141). Le pipeline échouait donc AU MOMENT MÊME où le module était
# chargé, et la ligne affichait « pilote non chargé » à tort (mesuré 20/09).
# C'est aussi la source que lit le plugin, donc les deux disent la même chose.
if grep -q '^hid_playstation ' /proc/modules 2>/dev/null; then
    row "DualSense" "${c_ok}pilote prêt${c_z} · ${ds_count:-0} connectée(s)"
else
    row "DualSense" "${c_dim}pilote hid_playstation non chargé${c_z}"
fi

# Le statut DRM est fiable; les capacités DSC/CEC demandent une TV et un
# adaptateur réellement branchés, donc ne sont pas déduites ici.
display_connected=0
for status in /sys/class/drm/card*-*/status; do
    [ -r "$status" ] || continue
    [ "$(cat "$status" 2>/dev/null)" = "connected" ] && display_connected=$((display_connected + 1))
done
if [ "$display_connected" -gt 0 ]; then
    row "Écran" "${c_ok}${display_connected} connectée(s)${c_z} · DSC/CEC à vérifier sur la TV"
else
    row "Écran" "${c_dim}aucun connecteur DRM actif${c_z}"
fi

# Garde-fou : on ne doit jamais suggérer de démasquer cecd sans bus /dev/cec*.
cec_dev=$(find /dev -maxdepth 1 -name 'cec*' -type c -print -quit 2>/dev/null)
if [ -n "$cec_dev" ]; then
    row "HDMI-CEC" "${c_ok}${cec_dev}${c_z} · intégration TV possible"
else
    row "HDMI-CEC" "${c_dim}aucun bus CEC détecté (TV/adaptateur non présent)${c_z}"
fi

# ── Proton-GE + plugins ───────────────────────────────────────────────────────
hdr "🎮 Proton-GE & plugins Decky"
compat="$TARGET_HOME/.steam/steam/compatibilitytools.d"
ge=$(ls -1 "$compat" 2>/dev/null | grep -i proton | sort -V | tail -1)
row "Proton-GE" "${ge:-${c_dim}aucun${c_z}}"
systemctl is-active --quiet plugin_loader 2>/dev/null && row "DeckyLoader" "${c_ok}actif${c_z}" || row "DeckyLoader" "${c_dim}inactif${c_z}"
for p in BC250-Toolkit SkullKey Steamcord; do
    [ -d "$TARGET_HOME/homebrew/plugins/$p" ] && row "  plugin $p" "${c_ok}installé${c_z}" || row "  plugin $p" "${c_dim}absent${c_z}"
done

echo
echo "${c_dim}  Astuce : si le CPU/GPU dépasse ~90°C en jeu, vérifie l'aération/pâte thermique.${c_z}"

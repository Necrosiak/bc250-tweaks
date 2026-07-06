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
pgrep -x gamemoded >/dev/null 2>&1 && row "gamemoded" "${c_ok}actif${c_z}" || row "gamemoded" "${c_dim}inactif${c_z}"
grep -q "zswap.enabled=1" /proc/cmdline 2>/dev/null && row "zswap" "${c_ok}activé${c_z}" || row "zswap" "${c_dim}off${c_z}"
grep -q "split_lock_detect=off" /proc/cmdline && row "split_lock_detect" "${c_ok}off (bon)${c_z}" || row "split_lock_detect" "${c_dim}on${c_z}"
[ -x /usr/local/bin/gamemoderun ] || command -v gamemoderun >/dev/null 2>&1 && row "gamemode (bin)" "${c_ok}présent${c_z}"

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

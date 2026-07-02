#!/bin/bash
# BC-250 tweaks — idempotent apply script
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS="$REPO_DIR/configs"

# Detect target user (first non-root user with UID >= 1000)
TARGET_USER="${SUDO_USER:-${USER:-bazzite}}"
if [ "$TARGET_USER" = "root" ]; then
    TARGET_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1; exit}')
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

log()  { echo "[+] $*"; }
skip() { echo "[=] $* (déjà OK)"; }
warn() { echo "[!] $*"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        warn "Ce script doit être lancé en root (sudo) pour appliquer les tweaks système."
        exit 1
    fi
}

# ── helper : copier un fichier seulement si différent ──────────────────────────
install_file() {
    local src="$1" dst="$2" mode="${3:-644}" owner="${4:-root:root}"
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" &>/dev/null; then
        install -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$src" "$dst"
        log "Installé : $dst"
    else
        skip "$dst"
    fi
}

install_user_file() {
    local src="$1" dst="$2" mode="${3:-644}"
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" &>/dev/null; then
        install -m "$mode" -o "$TARGET_USER" -g "$TARGET_USER" "$src" "$dst"
        log "Installé (user) : $dst"
    else
        skip "$dst"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. Profil tuned — géré par PPD sur Bazzite, on vérifie juste la config
# ══════════════════════════════════════════════════════════════════════════════
apply_tuned() {
    # Sur Bazzite, PPD gère tuned dynamiquement via /etc/tuned/ppd.conf :
    #   balanced   → balanced-bazzite       (repos)
    #   performance → throughput-performance-bazzite (jeu via gamemode)
    # Ne pas forcer le profil statiquement — PPD l'écraserait.
    if grep -q "throughput-performance-bazzite" /etc/tuned/ppd.conf 2>/dev/null; then
        skip "Tuned (géré par PPD — throughput-performance-bazzite actif en mode performance)"
    else
        warn "Tuned : /etc/tuned/ppd.conf introuvable ou mal configuré"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. Variables gaming (environment.d)
# ══════════════════════════════════════════════════════════════════════════════
apply_env_gaming() {
    install_user_file "$CONFIGS/gaming.conf" \
        "$TARGET_HOME/.config/environment.d/gaming.conf"
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. DRI config — unified heap APU (évite OOM VRAM sur les gros jeux)
# ══════════════════════════════════════════════════════════════════════════════
apply_drirc() {
    install_file "$CONFIGS/drirc" "/etc/drirc"
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. Pipewire latence
# ══════════════════════════════════════════════════════════════════════════════
apply_pipewire() {
    install_user_file "$CONFIGS/pipewire-gaming.conf" \
        "$TARGET_HOME/.config/pipewire/pipewire.conf.d/99-gaming-latency.conf"
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. Sysctl gaming
# ══════════════════════════════════════════════════════════════════════════════
apply_sysctl() {
    local dst="/etc/sysctl.d/99-bc250-gaming.conf"
    install_file "$CONFIGS/sysctl-gaming.conf" "$dst"
    sysctl --system -q 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. Kargs kernel (rpm-ostree)
# ══════════════════════════════════════════════════════════════════════════════
apply_kargs() {
    local need_kargs=0
    local kargs=(
        "amdgpu.ppfeaturemask=0xffffffff"
        # 8000 (et non 14750) : avec UMA Frame Buffer réservée au BIOS, la RAM
        # système tombe à ~11 Go → un gttsize=14750 dépasse la RAM et fait échouer
        # les allocs GTT (re-crash). 4 Go VRAM + 8 Go GTT = 12 Go VRAM totale.
        "amdgpu.gttsize=8000"
        "split_lock_detect=off"
        "transparent_hugepage=madvise"
        # Masque le spam console au boot — notamment le "RDSEED is not reliable on
        # this platform; disabling." que l'APU custom du BC-250 imprime 1×/cœur très
        # tôt (avant Plymouth). Ne SUPPRIME rien : tout reste dans `journalctl -b`,
        # c'est juste caché de l'écran. (À combiner avec `quiet`, déjà présent.)
        "loglevel=3"
    )
    local current_cmdline
    current_cmdline=$(cat /proc/cmdline)

    # Auto-réparation gttsize : la vérif ci-dessous est un grep de sous-chaîne, donc
    # si le cmdline contient une AUTRE valeur de gttsize (ex. ancien 14750, ou un
    # doublon issu d'un re-run d'une version antérieure du script), elle n'est jamais
    # nettoyée → kargs en conflit. On supprime ici toute occurrence de gttsize qui
    # n'est PAS la valeur voulue avant d'ajouter la bonne.
    local stale
    for stale in $(grep -o 'amdgpu\.gttsize=[0-9]*' /proc/cmdline | sort -u); do
        if [ "$stale" != "amdgpu.gttsize=8000" ]; then
            warn "Suppression d'un gttsize périmé/dupliqué : $stale"
            rpm-ostree kargs --delete-if-present="$stale"
        fi
    done
    current_cmdline=$(cat /proc/cmdline)

    for karg in "${kargs[@]}"; do
        if ! echo "$current_cmdline" | grep -q "$karg"; then
            need_kargs=1
            break
        fi
    done

    if [ "$need_kargs" -eq 1 ]; then
        local args=()
        for karg in "${kargs[@]}"; do
            if ! echo "$current_cmdline" | grep -q "$karg"; then
                args+=("--append=$karg")
            fi
        done
        rpm-ostree kargs "${args[@]}"
        warn "Kargs ajoutés — un reboot est nécessaire pour les activer."
    else
        skip "Kargs kernel (déjà dans /proc/cmdline)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. Gamemode (binaires dans /usr/local)
# ══════════════════════════════════════════════════════════════════════════════
apply_gamemode() {
    if [ -x /usr/local/bin/gamemoded ]; then
        skip "Gamemode (/usr/local/bin/gamemoded existe)"
        return
    fi

    log "Installation de gamemode depuis DNF (extraction manuelle)..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # Télécharger le RPM gamemode
    local rpm_url
    rpm_url=$(dnf download --url gamemode 2>/dev/null | grep '\.rpm$' | head -1) || true

    if [ -z "$rpm_url" ]; then
        warn "Impossible de trouver le RPM gamemode — installation via dnf download..."
        dnf download gamemode --destdir="$tmpdir" -q
        local rpm_file
        rpm_file=$(ls "$tmpdir"/*.rpm | head -1)
    else
        curl -sL "$rpm_url" -o "$tmpdir/gamemode.rpm"
        local rpm_file="$tmpdir/gamemode.rpm"
    fi

    if [ ! -f "${rpm_file:-}" ]; then
        warn "RPM gamemode introuvable — gamemode non installé."
        return 1
    fi

    # Extraire dans tmpdir
    rpm2cpio "$rpm_file" | cpio -idm -D "$tmpdir" --quiet 2>/dev/null

    # Copier binaires
    for bin in gamemoded gamemoderun gamemodelist; do
        [ -f "$tmpdir/usr/bin/$bin" ] && install -m 755 "$tmpdir/usr/bin/$bin" /usr/local/bin/ && log "  → /usr/local/bin/$bin"
    done

    # Copier libs
    mkdir -p /usr/local/lib64
    find "$tmpdir/usr/lib64" -name "libgamemode*" -exec install -m 755 {} /usr/local/lib64/ \; 2>/dev/null || true
    find "$tmpdir/usr/lib"   -name "libgamemode*" -exec install -m 755 {} /usr/local/lib64/ \; 2>/dev/null || true

    # Copier libexec helpers
    mkdir -p /usr/local/libexec
    for helper in cpugovctl cpucorectl gpuclockctl procsysctl; do
        local found
        found=$(find "$tmpdir" -name "$helper" 2>/dev/null | head -1)
        [ -n "$found" ] && install -m 755 "$found" /usr/local/libexec/ && log "  → /usr/local/libexec/$helper"
    done

    # ldconfig
    echo "/usr/local/lib64" > /etc/ld.so.conf.d/usrlocal.conf
    ldconfig

    log "Gamemode installé dans /usr/local"
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. Gamemode config + switch scripts
# ══════════════════════════════════════════════════════════════════════════════
apply_gamemode_config() {
    install_file "$CONFIGS/gamemode.ini" "/etc/gamemode.ini"
    install_file "$CONFIGS/gamemode-start.sh" "/usr/local/bin/gamemode-start.sh" "755"
    install_file "$CONFIGS/gamemode-end.sh"   "/usr/local/bin/gamemode-end.sh"   "755"
}

# ══════════════════════════════════════════════════════════════════════════════
# 8. Service systemd user : gamemoded
# ══════════════════════════════════════════════════════════════════════════════
apply_gamemoded_service() {
    local dst="$TARGET_HOME/.config/systemd/user/gamemoded.service"
    install_user_file "$CONFIGS/gamemoded.service" "$dst"
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user enable --now gamemoded.service 2>/dev/null || true
    log "Service gamemoded activé"
}

# ══════════════════════════════════════════════════════════════════════════════
# 9. HHD state — profil balanced
# ══════════════════════════════════════════════════════════════════════════════
apply_hhd() {
    local hhd_state="/etc/hhd/state.yml"
    if [ -f "$hhd_state" ]; then
        if grep -q "profile: balanced" "$hhd_state"; then
            skip "HHD (balanced déjà configuré)"
        else
            sed -i 's/profile: .*/profile: balanced/' "$hhd_state"
            log "HHD → balanced"
        fi
    else
        skip "HHD ($hhd_state introuvable — HHD non installé ?)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 10. scx_loader
# ══════════════════════════════════════════════════════════════════════════════
apply_scx() {
    install_file "$CONFIGS/scx_loader.toml" "/etc/scx_loader/config.toml"
    systemctl enable --now scx_loader.service 2>/dev/null || true
    # scx_loader (Type=dbus) ne charge AUCUN scheduler au boot : il reste on-demand.
    # Le flag --auto désactiverait l'interface D-Bus (scxctl/Steam perdraient le contrôle).
    # → service oneshot qui appelle scxctl start au boot (D-Bus préservé).
    install_file "$CONFIGS/bc250-scx-autostart.service" "/etc/systemd/system/bc250-scx-autostart.service"
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now bc250-scx-autostart.service 2>/dev/null || true
    log "scx_loader activé + autostart scx_lavd au boot"
}

# ══════════════════════════════════════════════════════════════════════════════
# 11. MangoHud
# ══════════════════════════════════════════════════════════════════════════════
apply_mangohud() {
    install_user_file "$CONFIGS/MangoHud.conf" \
        "$TARGET_HOME/.config/MangoHud/MangoHud.conf"
}

# ══════════════════════════════════════════════════════════════════════════════
# 12. vkBasalt
# ══════════════════════════════════════════════════════════════════════════════
apply_vkbasalt() {
    install_user_file "$CONFIGS/vkBasalt.conf" \
        "$TARGET_HOME/.config/vkBasalt.conf"
}

# ══════════════════════════════════════════════════════════════════════════════
# 13. Proton-GE (dernière version depuis GitHub)
# ══════════════════════════════════════════════════════════════════════════════
apply_proton_ge() {
    local compat_dir="$TARGET_HOME/.steam/steam/compatibilitytools.d"
    mkdir -p "$compat_dir"

    # Récupérer la dernière release
    local latest
    latest=$(curl -s "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4) || true

    if [ -z "$latest" ]; then
        warn "Impossible de récupérer la version Proton-GE (pas de réseau ?)"
        return
    fi

    local dest="$compat_dir/$latest"
    if [ -d "$dest" ]; then
        skip "Proton-GE ($latest déjà installé)"
        return
    fi

    log "Téléchargement Proton-GE $latest..."
    local url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${latest}/${latest}.tar.gz"
    local tmpfile
    tmpfile=$(mktemp /tmp/proton-ge-XXXXXX.tar.gz)
    curl -sL "$url" -o "$tmpfile"
    tar -xzf "$tmpfile" -C "$compat_dir"
    rm -f "$tmpfile"
    chown -R "$TARGET_USER:$TARGET_USER" "$dest"
    log "Proton-GE $latest installé dans $compat_dir"
}

# ══════════════════════════════════════════════════════════════════════════════
# 14. bc250-cu-live-manager (gestionnaire de CU/WGP via UMR)
# ══════════════════════════════════════════════════════════════════════════════
apply_umr_sudoers() {
    local sudoers_file="/etc/sudoers.d/bc250-umr"
    local expected_line="$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/umr"

    if [ -f "$sudoers_file" ] && grep -qF "$expected_line" "$sudoers_file" 2>/dev/null; then
        skip "sudoers umr ($sudoers_file déjà configuré)"
        return
    fi

    echo "$expected_line" > "$sudoers_file"
    chmod 440 "$sudoers_file"
    log "sudoers umr configuré : $TARGET_USER peut lancer umr sans mot de passe"
}

apply_cu_boot_sudoers() {
    local sudoers_file="/etc/sudoers.d/bc250-cu-boot"
    local marker="bc250-cu-boot-sudoers-v1"

    if [ -f "$sudoers_file" ] && grep -qF "$marker" "$sudoers_file" 2>/dev/null; then
        skip "sudoers cu-boot ($sudoers_file déjà configuré)"
        return
    fi

    cat > "$sudoers_file" <<EOF
# $marker — BC250-Toolkit-Decky : persistance profil CU au boot
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/tee /usr/local/bin/bc250-cu-restore
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/chmod 755 /usr/local/bin/bc250-cu-restore
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/tee /etc/systemd/system/bc250-cu-profile.service
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/systemctl daemon-reload
$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/systemctl enable bc250-cu-profile.service
EOF
    chmod 440 "$sudoers_file"
    log "sudoers cu-boot configuré : $TARGET_USER peut écrire le service CU boot sans mot de passe"
}

apply_cu_manager() {
    local dst="/usr/local/bin/bc250-cu-live-manager"

    if [ -x "$dst" ]; then
        skip "bc250-cu-live-manager ($dst déjà installé)"
        return
    fi

    # Priorité : copie locale si présente
    local local_src="$TARGET_HOME/bc250-cu-live-manager.sh"
    if [ -f "$local_src" ]; then
        install -m 0755 "$local_src" "$dst"
        log "bc250-cu-live-manager installé depuis $local_src"
        return
    fi

    # Sinon télécharger depuis GitHub (WinnieLV/bc250-cu-live-manager)
    log "Téléchargement de bc250-cu-live-manager depuis GitHub..."
    local url="https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/main/bc250-cu-live-manager.sh"
    if curl -sL "$url" -o "$dst" 2>/dev/null && [ -s "$dst" ]; then
        chmod 0755 "$dst"
        log "bc250-cu-live-manager installé dans $dst"
    else
        rm -f "$dst"
        warn "Impossible d'installer bc250-cu-live-manager (pas de réseau ?)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
    need_root

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  BC-250 Tweaks — apply.sh"
    echo "  Utilisateur cible : $TARGET_USER ($TARGET_HOME)"
    echo "═══════════════════════════════════════════════════"
    echo ""

    apply_tuned
    apply_env_gaming
    apply_drirc
    apply_pipewire
    apply_sysctl
    apply_kargs
    apply_gamemode
    apply_gamemode_config
    apply_gamemoded_service
    apply_hhd
    apply_scx
    apply_mangohud
    apply_vkbasalt
    apply_proton_ge
    apply_umr_sudoers
    apply_cu_boot_sudoers
    apply_cu_manager

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Terminé."
    echo "  Si des kargs ont été ajoutés, redémarre la machine."
    echo "═══════════════════════════════════════════════════"
}

main "$@"

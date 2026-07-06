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

# ══════════════════════════════════════════════════════════════════════════════
# 0. Détection de l'OS — applique la BONNE méthode selon la distro
# ══════════════════════════════════════════════════════════════════════════════
# Le BC-250 tourne sur plusieurs OS (doc communautaire : Bazzite, SteamOS,
# CachyOS/Arch, Fedora, Debian…). Chaque distro diffère sur : ① l'immutabilité
# (ostree ⇒ pas d'install de paquet classique, kargs via rpm-ostree), ② le
# gestionnaire de paquets, ③ la façon de poser des kargs kernel. On détecte tout
# ça une fois et les fonctions apply_* s'adaptent.
OS_ID="unknown"; OS_LIKE=""; OS_NAME="unknown"
IS_OSTREE=0; PKG_MGR="unknown"; KARG_METHOD="manual"

detect_os() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
        OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
    fi

    # Système immuable basé sur ostree (Bazzite, SteamOS, Silverblue/Kinoite…) :
    # le / est en lecture seule, on ne peut pas `dnf install` sans layering+reboot.
    if command -v rpm-ostree >/dev/null 2>&1 && { [ -d /run/ostree ] || [ -d /ostree ]; }; then
        IS_OSTREE=1
    fi

    # Gestionnaire de paquets
    if [ "$IS_OSTREE" -eq 1 ]; then
        PKG_MGR="rpm-ostree"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    fi

    # Méthode pour poser des arguments kernel (kargs) :
    #  - ostree      → rpm-ostree kargs (persistant, atomique)
    #  - grubby      → Fedora/RHEL mutables
    #  - grub        → /etc/default/grub + (update-grub|grub*-mkconfig) : Arch/Debian
    #  - manual      → bootloader non géré (systemd-boot, limine, rEFInd…) : on
    #                  affiche les kargs à ajouter à la main plutôt que risquer un
    #                  boot cassé.
    if [ "$IS_OSTREE" -eq 1 ]; then
        KARG_METHOD="rpm-ostree"
    elif command -v grubby >/dev/null 2>&1; then
        KARG_METHOD="grubby"
    elif [ -f /etc/default/grub ] && \
         { command -v update-grub >/dev/null 2>&1 || \
           command -v grub-mkconfig >/dev/null 2>&1 || \
           command -v grub2-mkconfig >/dev/null 2>&1; }; then
        KARG_METHOD="grub"
    else
        KARG_METHOD="manual"
    fi
}

# ── kernel args : helpers indépendants du bootloader ───────────────────────────
_grub_cfg_path() {
    local p
    for p in /boot/grub2/grub.cfg /boot/grub/grub.cfg \
             /boot/efi/EFI/*/grub.cfg /efi/EFI/*/grub.cfg; do
        [ -f "$p" ] && { echo "$p"; return; }
    done
    echo /boot/grub/grub.cfg
}

_grub_regen() {
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o "$(_grub_cfg_path)"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o "$(_grub_cfg_path)"
    fi
}

# Ajoute dans GRUB_CMDLINE_LINUX_DEFAULT de /etc/default/grub les args manquants.
_grub_append_args() {
    local f="/etc/default/grub"
    [ -f "$f" ] || { warn "$f absent — kargs GRUB non posés"; return 1; }
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$f" || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$f"
    # awk : réécrit la ligne en ajoutant les args absents, en préservant les guillemets
    local tmp; tmp=$(mktemp)
    awk -v add="$*" '
        /^GRUB_CMDLINE_LINUX_DEFAULT=/ {
            line=$0
            q=index(line,"\""); q2=(q ? index(substr(line,q+1),"\"")+q : 0)
            inner=(q && q2>q ? substr(line,q+1,q2-q-1) : "")
            n=split(inner, cur, /[ \t]+/)
            # set existant
            for (i=1;i<=n;i++) if (cur[i]!="") seen[cur[i]]=1
            out=inner
            m=split(add, a, /[ \t]+/)
            for (i=1;i<=m;i++) if (a[i]!="" && !(a[i] in seen)) { out=(out=="" ? a[i] : out" "a[i]); seen[a[i]]=1 }
            print "GRUB_CMDLINE_LINUX_DEFAULT=\"" out "\""
            next
        }
        { print }
    ' "$f" > "$tmp" && install -m 644 "$tmp" "$f"
    rm -f "$tmp"
}

_grub_remove_arg() {
    local f="/etc/default/grub" arg="$1"
    [ -f "$f" ] || return 0
    local tmp; tmp=$(mktemp)
    awk -v rm="$arg" '
        /^GRUB_CMDLINE_LINUX_DEFAULT=/ {
            line=$0
            q=index(line,"\""); q2=(q ? index(substr(line,q+1),"\"")+q : 0)
            inner=(q && q2>q ? substr(line,q+1,q2-q-1) : "")
            n=split(inner, cur, /[ \t]+/); out=""
            for (i=1;i<=n;i++) if (cur[i]!="" && cur[i]!=rm) out=(out=="" ? cur[i] : out" "cur[i])
            print "GRUB_CMDLINE_LINUX_DEFAULT=\"" out "\""
            next
        }
        { print }
    ' "$f" > "$tmp" && install -m 644 "$tmp" "$f"
    rm -f "$tmp"
}

# Ajoute une liste de kargs (déjà filtrés = seulement les manquants). Renvoie 0
# si posés, 1 si méthode manuelle (l'appelant affiche alors les instructions).
karg_add_all() {
    case "$KARG_METHOD" in
        rpm-ostree)
            local a=(); local k
            for k in "$@"; do a+=("--append=$k"); done
            rpm-ostree kargs "${a[@]}"
            ;;
        grubby)
            grubby --update-kernel=ALL --args="$*"
            ;;
        grub)
            _grub_append_args "$@" && _grub_regen
            ;;
        *)
            return 1
            ;;
    esac
}

karg_remove() {
    case "$KARG_METHOD" in
        rpm-ostree) rpm-ostree kargs --delete-if-present="$1" ;;
        grubby)     grubby --update-kernel=ALL --remove-args="$1" ;;
        grub)       _grub_remove_arg "$1" && _grub_regen ;;
    esac
}

# ── paquets : installe un paquet natif (hors ostree) ───────────────────────────
pkg_install() {
    # $@ = noms de paquet (mêmes noms sur dnf/pacman/apt pour gamemode)
    case "$PKG_MGR" in
        dnf)    dnf install -y "$@" ;;
        pacman) pacman -S --needed --noconfirm "$@" ;;
        apt)    apt-get update -qq && apt-get install -y "$@" ;;
        *)      return 1 ;;
    esac
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
# 5. Kargs kernel (méthode auto : rpm-ostree / grubby / GRUB / manuel)
# ══════════════════════════════════════════════════════════════════════════════
apply_kargs() {
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

    if [ "$KARG_METHOD" = "manual" ]; then
        warn "Bootloader non géré automatiquement (ni ostree, ni grubby, ni GRUB)."
        warn "Ajoute ces kargs à la main dans ton bootloader (systemd-boot, limine…) :"
        printf '        %s\n' "${kargs[@]}"
        return
    fi

    # Auto-réparation gttsize : si le cmdline contient une AUTRE valeur de gttsize
    # (ancien 14750, ou doublon d'un re-run), elle n'est jamais nettoyée par le
    # grep de sous-chaîne ci-dessous → kargs en conflit. On retire d'abord toute
    # occurrence de gttsize qui n'est PAS la valeur voulue.
    local stale
    for stale in $(grep -o 'amdgpu\.gttsize=[0-9]*' /proc/cmdline | sort -u); do
        if [ "$stale" != "amdgpu.gttsize=8000" ]; then
            warn "Suppression d'un gttsize périmé/dupliqué : $stale"
            karg_remove "$stale"
        fi
    done

    local current_cmdline karg
    current_cmdline=$(cat /proc/cmdline)
    local missing=()
    for karg in "${kargs[@]}"; do
        echo "$current_cmdline" | grep -q -- "$karg" || missing+=("$karg")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        skip "Kargs kernel (déjà dans /proc/cmdline)"
        return
    fi

    if karg_add_all "${missing[@]}"; then
        log "Kargs posés via ${KARG_METHOD} : ${missing[*]}"
        warn "Un reboot est nécessaire pour les activer."
    else
        warn "Échec de la pose des kargs (méthode ${KARG_METHOD}) — à ajouter à la main :"
        printf '        %s\n' "${missing[@]}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. Gamemode
#   - OS mutable (Arch/CachyOS/Fedora/Debian) : installé nativement par le
#     gestionnaire de paquets, gamemoded arrive dans /usr/bin.
#   - OS immuable (Bazzite/SteamOS) : / est en lecture seule → on extrait le RPM
#     dans /usr/local (le seul chemin inscriptible et dans le PATH).
# GAMEMODED_BIN pointe ensuite sur le binaire réel pour le service systemd.
# ══════════════════════════════════════════════════════════════════════════════
GAMEMODED_BIN=""

apply_gamemode() {
    # Déjà présent (natif ou extrait) ?
    if command -v gamemoded >/dev/null 2>&1; then
        GAMEMODED_BIN=$(command -v gamemoded)
        skip "Gamemode ($GAMEMODED_BIN existe)"
        return
    fi
    if [ -x /usr/local/bin/gamemoded ]; then
        GAMEMODED_BIN=/usr/local/bin/gamemoded
        skip "Gamemode (/usr/local/bin/gamemoded existe)"
        return
    fi

    # OS mutable : installation native (propre, mises à jour gérées par la distro).
    if [ "$IS_OSTREE" -eq 0 ] && [ "$PKG_MGR" != "unknown" ]; then
        log "Installation de gamemode via $PKG_MGR..."
        if pkg_install gamemode && command -v gamemoded >/dev/null 2>&1; then
            GAMEMODED_BIN=$(command -v gamemoded)
            log "Gamemode installé ($GAMEMODED_BIN)"
            return
        fi
        warn "Installation native de gamemode échouée — tentative d'extraction RPM..."
    fi

    # OS immuable (ou fallback) : extraction manuelle d'un RPM dans /usr/local.
    # Nécessite dnf (présent sur Bazzite/Fedora). Sinon on abandonne proprement.
    if ! command -v dnf >/dev/null 2>&1; then
        warn "gamemode non installable (ni paquet natif, ni dnf pour extraction) — ignoré."
        return
    fi
    log "Installation de gamemode depuis DNF (extraction manuelle dans /usr/local)..."
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

    [ -x /usr/local/bin/gamemoded ] && GAMEMODED_BIN=/usr/local/bin/gamemoded
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
    # Sans binaire gamemoded (install échouée) : pas de service.
    local bin="${GAMEMODED_BIN:-}"
    [ -n "$bin" ] || bin=$(command -v gamemoded 2>/dev/null || true)
    [ -n "$bin" ] || { [ -x /usr/local/bin/gamemoded ] && bin=/usr/local/bin/gamemoded; }
    if [ -z "$bin" ]; then
        warn "gamemoded introuvable — service non installé."
        return
    fi

    local dst="$TARGET_HOME/.config/systemd/user/gamemoded.service"
    # Le service livré vise /usr/local/bin/gamemoded (cas ostree) ; sur OS mutable
    # le binaire est dans /usr/bin → on réécrit l'ExecStart vers le chemin réel.
    local tmp; tmp=$(mktemp)
    sed "s#^ExecStart=.*#ExecStart=$bin#" "$CONFIGS/gamemoded.service" > "$tmp"
    install_user_file "$tmp" "$dst"
    rm -f "$tmp"
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
        systemctl --user enable --now gamemoded.service 2>/dev/null || true
    log "Service gamemoded activé ($bin)"
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
# 15. bc250-uma-helper (écriture UMA Frame Buffer via efivar AmdSetup — Toolkit)
# ══════════════════════════════════════════════════════════════════════════════
apply_uma_helper() {
    install_file "$CONFIGS/bc250-uma-helper" /usr/local/bin/bc250-uma-helper 755
}

apply_uma_sudoers() {
    local sudoers_file="/etc/sudoers.d/bc250-uma"
    local marker="bc250-uma-sudoers-v1"

    if [ -f "$sudoers_file" ] && grep -qF "$marker" "$sudoers_file" 2>/dev/null; then
        skip "sudoers uma ($sudoers_file déjà configuré)"
        return
    fi

    cat > "$sudoers_file" <<EOF
# $marker — BC250-Toolkit-Decky : lecture/écriture UMA (efivar AmdSetup)
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/bc250-uma-helper
EOF
    chmod 440 "$sudoers_file"
    log "sudoers uma configuré : $TARGET_USER peut lancer bc250-uma-helper sans mot de passe"
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
    need_root
    detect_os

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  BC-250 Tweaks — apply.sh"
    echo "  Utilisateur cible : $TARGET_USER ($TARGET_HOME)"
    echo "  OS : $OS_NAME (id=$OS_ID$([ -n "$OS_LIKE" ] && echo ", like=$OS_LIKE"))"
    echo "  Immuable : $([ "$IS_OSTREE" -eq 1 ] && echo oui || echo non)"\
"  ·  Paquets : $PKG_MGR  ·  Kargs : $KARG_METHOD"
    echo "═══════════════════════════════════════════════════"
    echo ""

    if [ "$IS_OSTREE" -eq 0 ] && [[ "$OS_ID" != "bazzite" && "$OS_LIKE" != *fedora* ]]; then
        warn "OS hors Bazzite/SteamOS : support best-effort (validé par les retours"
        warn "de la communauté). Signale tout souci : github.com/Necrosiak/bc250-tweaks/issues"
        echo ""
    fi

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
    apply_uma_helper
    apply_uma_sudoers

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Terminé."
    echo "  Si des kargs ont été ajoutés, redémarre la machine."
    echo "═══════════════════════════════════════════════════"
}

main "$@"

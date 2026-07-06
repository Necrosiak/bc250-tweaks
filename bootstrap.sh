#!/bin/bash
# Bootstrap : à lancer une seule fois sur une install Bazzite fraîche
# Usage : curl -sL https://raw.githubusercontent.com/Necrosiak/bc250-tweaks/main/bootstrap.sh | sudo bash
set -euo pipefail

REPO_URL="https://github.com/Necrosiak/bc250-tweaks.git"
INSTALL_DIR="/opt/bc250-tweaks"
SERVICE_SRC="$INSTALL_DIR/systemd/bc250-tweaks.service"
SERVICE_DST="/etc/systemd/system/bc250-tweaks.service"

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Lance ce script en root : sudo bash bootstrap.sh"
    exit 1
fi

# Installer git si absent — méthode selon l'OS
if ! command -v git &>/dev/null; then
    echo "[+] Installation de git..."
    if command -v rpm-ostree &>/dev/null && { [ -d /run/ostree ] || [ -d /ostree ]; }; then
        rpm-ostree install git
        echo "[!] Reboot requis pour finaliser l'install de git, puis relance bootstrap.sh"
        exit 0
    elif command -v dnf &>/dev/null; then
        dnf install -y git
    elif command -v pacman &>/dev/null; then
        pacman -S --needed --noconfirm git
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y git
    else
        echo "[!] Gestionnaire de paquets inconnu — installe git à la main puis relance."
        exit 1
    fi
fi

# Clone ou update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "[=] Repo déjà cloné — mise à jour..."
    git -C "$INSTALL_DIR" pull origin main
else
    echo "[+] Clonage du repo..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/apply.sh" "$INSTALL_DIR/update.sh"

# Installer le service systemd
echo "[+] Installation du service systemd..."
cp "$SERVICE_SRC" "$SERVICE_DST"
systemctl daemon-reload
systemctl enable bc250-tweaks.service

# Premier apply immédiat
echo "[+] Premier apply..."
"$INSTALL_DIR/apply.sh"

echo ""
echo "Bootstrap terminé."
echo "Tweaks système + DeckyLoader + plugins (BC250-Toolkit, SkullKey, Steamcord)"
echo "installés — setup BC-250 complet. Le service bc250-tweaks se relance à chaque boot."
echo "Logs : journalctl -u bc250-tweaks -f  ou  tail -f /var/log/bc250-tweaks.log"

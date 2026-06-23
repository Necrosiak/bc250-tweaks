#!/bin/bash
# Appelé par le service systemd au boot : git pull + apply
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/var/log/bc250-tweaks.log"

exec >> "$LOG" 2>&1
echo ""
echo "══════════════════════════════════════════"
echo "  $(date '+%Y-%m-%d %H:%M:%S') — update.sh"
echo "══════════════════════════════════════════"

# Pull seulement si on a le réseau
if ! ping -c1 -W3 github.com &>/dev/null; then
    echo "[!] Pas de réseau — skip git pull, on applique le local"
else
    cd "$REPO_DIR"
    git fetch origin main --quiet
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "[+] Mise à jour disponible — pull..."
        git pull origin main --quiet
    else
        echo "[=] Repo déjà à jour ($LOCAL)"
    fi
fi

"$REPO_DIR/apply.sh"

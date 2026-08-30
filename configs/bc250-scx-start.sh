#!/usr/bin/bash
# BC-250 — démarrage prudent du scheduler scx_lavd.
#
# scx_lavd apporte un ordonnancement orienté latence, mais sur cette carte il
# lui arrive d'être ÉVINCÉ par le noyau (« runnable task stall ») : une tâche
# n'est pas ordonnancée pendant 35 à 45 secondes, toute l'interface gèle, puis
# scx_loader relance et le cycle recommence. Mesuré le 30/08/2026 sur
# kernel 7.2.1-ogc2 avec scx-scheds 1.1.3-3, en --autopower ET en --performance
# (les victimes relevées : winedevice.exe, systemd-userwork, un thread Steam).
#
# On ne devine donc pas la version fautive : le service OBSERVE. Si le boot
# précédent a subi au moins deux évictions, il se désarme et laisse la main à
# l'ordonnanceur du noyau (EEVDF) plutôt que d'imposer des gels à répétition.
# Réarmement : supprimer le fichier d'état.
set -u
STATE=/var/lib/bc250-scx
FLAG="$STATE/disabled"
THRESHOLD=2

log() { printf 'bc250-scx: %s\n' "$*"; }

mkdir -p "$STATE"

if [ -f "$FLAG" ]; then
    log "désarmé — $(cat "$FLAG" 2>/dev/null)"
    log "pour réessayer : sudo rm $FLAG puis redémarrer"
    exit 0
fi

count_stalls() {
    journalctl -b "$1" -k --no-pager 2>/dev/null | grep -c 'runnable task stall' || true
}
prev=$(count_stalls -1); case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
# Le boot COURANT compte aussi : ce script est également appelé par apply.sh, et
# recharger un scheduler qui a déjà calé dans cette session-ci ne ferait que
# rendre la machine à ses gels jusqu'au prochain redémarrage.
cur=$(count_stalls 0);  case "$cur"  in ''|*[!0-9]*) cur=0 ;;  esac

if [ $((prev + cur)) -ge "$THRESHOLD" ]; then
    printf 'désarmé le %s : %s évictions au boot précédent, %s sur celui-ci\n' \
        "$(date -Is)" "$prev" "$cur" > "$FLAG"
    log "$prev éviction(s) au boot précédent + $cur sur celui-ci → scx_lavd NON chargé, on garde EEVDF"
    log "état : $FLAG"
    exit 0
fi
if [ "$cur" -ge 1 ]; then
    log "$cur éviction déjà survenue sur ce boot → scx_lavd non rechargé maintenant"
    exit 0
fi

log "démarrage de scx_lavd (aucune éviction relevée)"
exec scxctl start --sched scx_lavd

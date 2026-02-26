#!/bin/bash
set -euo pipefail

TARGET_USER="${TARGET_USER:-ubuntu}"
SSH_OPTS="${SSH_OPTS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR }"
WAIT_BETWEEN="${WAIT_BETWEEN:-4}"

DRY_RUN=0
SKIP_CONFIRM=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --yes)
      SKIP_CONFIRM=1
      ;;
    --help|-h)
      cat <<'EOF'
Usage: ./restart_swarm_cluster.sh [--dry-run] [--yes]

Startet das komplette Docker-Swarm-Cluster neu:
1) rebootet alle Worker-Nodes
2) rebootet den lokalen Manager als letztes

Optionen:
  --dry-run   Zeigt nur, was gemacht würde
  --yes       Keine interaktive Bestätigung

Umgebungsvariablen:
  TARGET_USER   SSH-User für alle Nodes (Default: ubuntu)
  SSH_OPTS      Zusätzliche SSH-Optionen
  WAIT_BETWEEN  Sekunden Pause zwischen Worker-Reboots (Default: 4)
EOF
      exit 0
      ;;
    *)
      echo "🟥 Unbekanntes Argument: $arg"
      exit 1
      ;;
  esac
done

log() { echo -e "🟦 $*"; }
ok() { echo -e "✅ $*"; }
warn() { echo -e "🟨 $*"; }
die() { echo -e "🟥 $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Fehlendes Kommando: $1"; }

need_cmd docker
need_cmd ssh

if ! docker info >/dev/null 2>&1; then
  die "Docker ist lokal nicht verfügbar. Script auf einem Swarm-Manager ausführen."
fi

if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)" != "active" ]]; then
  die "Dieser Host ist nicht Teil eines aktiven Swarm."
fi

if [[ "$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || true)" != "true" ]]; then
  die "Dieser Host ist kein Manager. Script auf einem Manager ausführen."
fi

MANAGER_HOSTNAME="$(hostname -s)"
MANAGER_ADDR="$(docker info --format '{{.Swarm.NodeAddr}}')"

mapfile -t WORKER_LINES < <(docker node ls --format '{{.Hostname}}|{{.ManagerStatus}}' | awk -F'|' '$2=="" {print $1}')

WORKER_COUNT="${#WORKER_LINES[@]}"
log "Manager: ${MANAGER_HOSTNAME} (${MANAGER_ADDR})"
log "Gefundene Worker: ${WORKER_COUNT}"

if (( WORKER_COUNT > 0 )); then
  log "Worker-Liste:"
  for worker in "${WORKER_LINES[@]}"; do
    worker_name="${worker%%|*}"
    worker_addr="$(docker node inspect --format '{{.Status.Addr}}' "$worker_name")"
    echo "  - ${worker_name} (${worker_addr})"
  done
fi

if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
  echo
  read -r -p "Das gesamte Cluster wird neu gestartet. Fortfahren? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      warn "Abgebrochen"
      exit 0
      ;;
  esac
fi

if (( WORKER_COUNT > 0 )); then
  for worker in "${WORKER_LINES[@]}"; do
    worker_name="${worker%%|*}"
    worker_addr="$(docker node inspect --format '{{.Status.Addr}}' "$worker_name")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[DRY-RUN] reboot ${TARGET_USER}@${worker_addr} (${worker_name})"
      continue
    fi

    log "Reboote Worker ${worker_name} (${worker_addr}) ..."
    if ssh $SSH_OPTS "${TARGET_USER}@${worker_addr}" 'sudo nohup bash -c "sleep 1; reboot" >/dev/null 2>&1 &' ; then
      ok "Reboot ausgelöst für ${worker_name}"
    else
      warn "Konnte ${worker_name} nicht per SSH triggern"
    fi

    sleep "$WAIT_BETWEEN"
  done
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "[DRY-RUN] lokaler Manager-Reboot (${MANAGER_HOSTNAME})"
  ok "Dry-run abgeschlossen"
  exit 0
fi

warn "Reboote lokalen Manager ${MANAGER_HOSTNAME} als letzten Schritt ..."
sudo nohup bash -c "sleep 2; reboot" >/dev/null 2>&1 &
ok "Manager-Reboot ausgelöst. SSH-Verbindung kann jetzt abbrechen."

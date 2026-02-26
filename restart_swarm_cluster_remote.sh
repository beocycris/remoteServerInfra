#!/bin/bash
set -euo pipefail

TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOST="${TARGET_HOST:-}"
SSH_OPTS="${SSH_OPTS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR }"
WAIT_BETWEEN_WORKERS="${WAIT_BETWEEN_WORKERS:-4}"
WAIT_MANAGER_UP_TIMEOUT="${WAIT_MANAGER_UP_TIMEOUT:-600}"
WAIT_CLUSTER_TIMEOUT="${WAIT_CLUSTER_TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

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
Usage: TARGET_HOST=<MANAGER_IP> ./restart_swarm_cluster_remote.sh [--dry-run] [--yes]

Remote-Variante (von Workstation/Mac aus):
1) rebootet alle Worker-Nodes
2) rebootet den Manager als letztes
3) wartet automatisch auf Manager-SSH
4) wartet auf Cluster-Ready + Service-Konvergenz
5) zeigt Status (docker node ls, docker service ls)

Optionen:
  --dry-run   Zeigt nur, was gemacht würde
  --yes       Keine interaktive Bestätigung

Umgebungsvariablen:
  TARGET_HOST             Manager-IP oder Hostname (pflicht)
  TARGET_USER             SSH-User (Default: ubuntu)
  SSH_OPTS                Zusätzliche SSH-Optionen
  WAIT_BETWEEN_WORKERS    Pause zwischen Worker-Reboots in Sekunden (Default: 4)
  WAIT_MANAGER_UP_TIMEOUT Timeout für Manager-SSH-Reconnect in Sekunden (Default: 600)
  WAIT_CLUSTER_TIMEOUT    Timeout für Cluster-Health in Sekunden (Default: 600)
  POLL_INTERVAL           Polling-Intervall in Sekunden (Default: 5)
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

need_cmd ssh
need_cmd awk

[[ -n "$TARGET_HOST" ]] || die "TARGET_HOST fehlt (Manager-IP/Hostname)."

remote() {
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "$@"
}

if ! remote 'docker info >/dev/null 2>&1'; then
  die "Docker auf Manager nicht erreichbar (${TARGET_USER}@${TARGET_HOST})."
fi

if [[ "$(remote "docker info --format '{{.Swarm.ControlAvailable}}'" 2>/dev/null || true)" != "true" ]]; then
  die "TARGET_HOST ist kein Swarm-Manager."
fi

MANAGER_NAME="$(remote 'hostname -s')"
EXPECTED_NODE_COUNT="$(remote "docker node ls --format '{{.Hostname}}' | wc -l | tr -d ' '")"

mapfile -t WORKERS < <(remote "docker node ls --format '{{.Hostname}}|{{.ManagerStatus}}' | awk -F'|' '\$2==\"\" {print \$1}'")

log "Manager: ${MANAGER_NAME} (${TARGET_HOST})"
log "Erwartete Nodes gesamt: ${EXPECTED_NODE_COUNT}"
log "Gefundene Worker: ${#WORKERS[@]}"

if (( ${#WORKERS[@]} > 0 )); then
  log "Worker-Liste:"
  for worker_name in "${WORKERS[@]}"; do
    worker_addr="$(remote "docker node inspect --format '{{.Status.Addr}}' '${worker_name}'")"
    echo "  - ${worker_name} (${worker_addr})"
  done
fi

if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
  echo
  read -r -p "Cluster-Reboot inkl. Auto-Healthcheck ausführen? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      warn "Abgebrochen"
      exit 0
      ;;
  esac
fi

if (( ${#WORKERS[@]} > 0 )); then
  for worker_name in "${WORKERS[@]}"; do
    worker_addr="$(remote "docker node inspect --format '{{.Status.Addr}}' '${worker_name}'")"

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
    sleep "$WAIT_BETWEEN_WORKERS"
  done
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "[DRY-RUN] reboot ${TARGET_USER}@${TARGET_HOST} (Manager ${MANAGER_NAME})"
  ok "Dry-run abgeschlossen"
  exit 0
fi

warn "Reboote Manager ${MANAGER_NAME} (${TARGET_HOST}) als letzten Schritt ..."
if remote 'sudo nohup bash -c "sleep 2; reboot" >/dev/null 2>&1 &' ; then
  ok "Manager-Reboot ausgelöst"
else
  die "Manager-Reboot konnte nicht ausgelöst werden"
fi

log "Warte auf SSH-Reconnect des Managers ..."
start_ts="$(date +%s)"
while true; do
  if remote 'echo up' >/dev/null 2>&1; then
    ok "Manager ist per SSH wieder erreichbar"
    break
  fi

  now_ts="$(date +%s)"
  elapsed="$((now_ts - start_ts))"
  if (( elapsed >= WAIT_MANAGER_UP_TIMEOUT )); then
    die "Timeout: Manager kam nicht innerhalb ${WAIT_MANAGER_UP_TIMEOUT}s zurück"
  fi
  sleep "$POLL_INTERVAL"
done

log "Warte auf Swarm- und Service-Health ..."
health_start_ts="$(date +%s)"
while true; do
  swarm_active="$(remote "docker info --format '{{.Swarm.LocalNodeState}}'" 2>/dev/null || true)"
  control_ok="$(remote "docker info --format '{{.Swarm.ControlAvailable}}'" 2>/dev/null || true)"
  ready_nodes="$(remote "docker node ls --format '{{.Status}}' | grep -c '^Ready$' || true")"

  services_ok=0
  if remote "docker service ls --format '{{.Name}} {{.Replicas}}' | awk '{split(\$2,a,\"/\"); if (a[1] != a[2]) bad=1} END{exit bad?1:0}'" >/dev/null 2>&1; then
    services_ok=1
  fi

  if [[ "$swarm_active" == "active" && "$control_ok" == "true" && "$ready_nodes" == "$EXPECTED_NODE_COUNT" && "$services_ok" -eq 1 ]]; then
    ok "Cluster ist wieder bereit (${ready_nodes}/${EXPECTED_NODE_COUNT} Nodes Ready, Services konvergiert)"
    break
  fi

  now_ts="$(date +%s)"
  elapsed="$((now_ts - health_start_ts))"
  if (( elapsed >= WAIT_CLUSTER_TIMEOUT )); then
    warn "Timeout beim Cluster-Healthcheck nach ${WAIT_CLUSTER_TIMEOUT}s"
    warn "Letzter Stand: swarm=${swarm_active}, control=${control_ok}, ready=${ready_nodes}/${EXPECTED_NODE_COUNT}, services_ok=${services_ok}"
    break
  fi

  sleep "$POLL_INTERVAL"
done

echo
log "Cluster-Status (Manager):"
remote 'docker node ls'
echo
remote 'docker service ls'

#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;34m🟦 $*\033[0m"; }
ok()   { echo -e "\033[1;32m✅ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $*\033[0m"; }
err()  { echo -e "\033[1;31m🟥 $*\033[0m"; }

[[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen"; exit 1; }

SWARM_ACTION="${SWARM_ACTION:-none}"
SWARM_ADVERTISE_ADDR="${SWARM_ADVERTISE_ADDR:-}"
SWARM_MANAGER_ADDR="${SWARM_MANAGER_ADDR:-}"
SWARM_JOIN_TOKEN="${SWARM_JOIN_TOKEN:-}"

if [[ "$SWARM_ACTION" == "none" ]]; then
  log "Swarm-Aktion: none (überspringe)"
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  err "Docker ist nicht verfügbar"
  exit 1
fi

if [[ -z "$SWARM_ADVERTISE_ADDR" ]]; then
  SWARM_ADVERTISE_ADDR="$(hostname -I | awk '{print $1}')"
fi

CURRENT_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

if [[ "$SWARM_ACTION" == "init" ]]; then
  if [[ "$CURRENT_STATE" == "active" ]]; then
    warn "Node ist bereits in einem Swarm – init übersprungen"
  else
    [[ -n "$SWARM_ADVERTISE_ADDR" ]] || { err "Keine Advertise-IP ermittelt"; exit 1; }
    log "Initialisiere Docker Swarm (advertise-addr: $SWARM_ADVERTISE_ADDR)"
    docker swarm init --advertise-addr "$SWARM_ADVERTISE_ADDR"
    ok "Swarm wurde initialisiert"
  fi

  log "Worker Join-Befehl:"
  docker swarm join-token worker | sed 's/^/   /'
  log "Manager Join-Befehl:"
  docker swarm join-token manager | sed 's/^/   /'
  exit 0
fi

if [[ "$SWARM_ACTION" == "join-worker" || "$SWARM_ACTION" == "join-manager" ]]; then
  [[ -n "$SWARM_MANAGER_ADDR" ]] || { err "SWARM_MANAGER_ADDR fehlt"; exit 1; }
  
  if [[ -z "$SWARM_JOIN_TOKEN" ]]; then
    err "SWARM_JOIN_TOKEN leer – Token konnte nicht automatisch abgerufen werden"
    err "Bitte Token manuell abrufen und übergeben:"
    err ""
    err "  ssh ${SWARM_MANAGER_ADDR%:*} 'docker swarm join-token ${SWARM_ACTION#join-} -q'"
    err ""
    err "Dann mit Token erneut aufrufen:"
    err "  SWARM_JOIN_TOKEN=<TOKEN> SWARM_ACTION=$SWARM_ACTION SWARM_MANAGER_ADDR=$SWARM_MANAGER_ADDR sudo $0"
    err ""
    exit 1
  fi

  if [[ "$CURRENT_STATE" == "active" ]]; then
    warn "Node ist bereits in einem Swarm – join übersprungen"
    exit 0
  fi

  log "Führe Swarm-Join aus: $SWARM_ACTION"
  docker swarm join --token "$SWARM_JOIN_TOKEN" "$SWARM_MANAGER_ADDR"
  ok "Swarm-Join erfolgreich"
  exit 0
fi
echo "🔎 Swarm Status"
docker info | grep Swarm

echo "🔎 Nodes"
docker node ls

echo "🔎 Disk"
df -h /

echo "🔎 Docker Space"
docker system df

echo "🔎 RAM"
free -h

echo "🔎 Overlay Networks"
docker network ls | grep overlay
err "Unbekannte SWARM_ACTION: $SWARM_ACTION"
exit 1

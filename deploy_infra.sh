#!/bin/bash
set -euo pipefail

# ====== Konfiguration ======
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOST="${TARGET_HOST:-10.10.100.164}"
TARGET_DIR="${TARGET_DIR:-/home/ubuntu/brewery-infra}"

SSH_OPTS="${SSH_OPTS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR }"

# ====== Flags ======
DO_CORE_ONLY=0
DO_HOTSPOT=0
DO_MONITORING=0

SWARM_ACTION="none"
SWARM_ADVERTISE_ADDR=""
SWARM_MANAGER_ADDR=""
SWARM_JOIN_TOKEN=""

for arg in "$@"; do
  case "$arg" in
    --core-only)
      DO_CORE_ONLY=1
      ;;
    --hotspot)
      DO_HOTSPOT=1
      ;;
    --monitoring)
      DO_MONITORING=1
      ;;
    --swarm-init)
      SWARM_ACTION="init"
      ;;
    --swarm-join-worker)
      SWARM_ACTION="join-worker"
      ;;
    --swarm-join-manager)
      SWARM_ACTION="join-manager"
      ;;
    --swarm-advertise-addr=*)
      SWARM_ADVERTISE_ADDR="${arg#*=}"
      ;;
    --swarm-manager-addr=*)
      SWARM_MANAGER_ADDR="${arg#*=}"
      ;;
    --swarm-join-token=*)
      SWARM_JOIN_TOKEN="${arg#*=}"
      ;;
    *)
      echo "🟥 Unbekanntes Argument: $arg"
      exit 1
      ;;
  esac
done

# ====== Flag-Validierung ======
if [[ "$DO_CORE_ONLY" -eq 0 && "$DO_HOTSPOT" -eq 0 && "$DO_MONITORING" -eq 0 ]]; then
  echo "🟥 Bitte ein Flag angeben:"
  echo "   --core-only | --hotspot | --monitoring"
  exit 1
fi

if [[ "$DO_CORE_ONLY" -eq 1 && "$DO_HOTSPOT" -eq 1 ]]; then
  echo "🟥 --core-only und --hotspot schließen sich gegenseitig aus"
  exit 1
fi

if [[ "$SWARM_ACTION" == "join-worker" || "$SWARM_ACTION" == "join-manager" ]]; then
  if [[ -z "$SWARM_MANAGER_ADDR" ]]; then
    echo "🟥 Für ${SWARM_ACTION} ist --swarm-manager-addr=<IP:2377> erforderlich"
    exit 1
  fi
fi

# ====== Helpers ======
log() { echo -e "🟦 $*"; }
warn() { echo -e "🟨 $*" >&2; }
die() { echo -e "🟥 $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Fehlendes Kommando: $1"; }

# Funktion zum Abrufen des Swarm-Join-Tokens vom Manager (mit Fallback)
fetch_swarm_token() {
  local manager_addr="$1"
  local token_type="$2"  # 'worker' oder 'manager'
  
  # IP:Port trennen
  local manager_ip="${manager_addr%:*}"
  
  log "Hole ${token_type}-Token vom Manager ($manager_ip)..."
  
  # Versuche Token via SSH abzurufen (nur den Token, keine zusätzliche Info)
  local token
  token=$(ssh $SSH_OPTS "${TARGET_USER}@${manager_ip}" "docker swarm join-token ${token_type} -q" 2>/dev/null) || {
    warn "Auto-Abruf des ${token_type}-Tokens fehlgeschlagen."
    return 1
  }
  
  if [[ -z "$token" ]]; then
    warn "Token vom Manager leer"
    return 1
  fi
  
  echo "$token"
  return 0
}

# ====== Checks lokal ======
need_cmd rsync
need_cmd ssh

# ====== Swarm Token automatisch abrufen (falls nicht angegeben) ======
if [[ "$SWARM_ACTION" == "join-worker" && -z "$SWARM_JOIN_TOKEN" ]]; then
  if SWARM_JOIN_TOKEN="$(fetch_swarm_token "$SWARM_MANAGER_ADDR" "worker")"; then
    warn "Worker-Token automatisch vom Manager abgerufen"
  else
    warn "Token-Abruf fehlgeschlagen – Fallback auf manuelle Methode"
    warn "Bitte Token manuell abrufen und übergeben:"
    warn ""
    warn "  ssh ${TARGET_USER}@${SWARM_MANAGER_ADDR%:*} \"docker swarm join-token worker -q\""
    warn ""
    warn "Dann Deploy mit Token wiederholen:"
    warn "  ./deploy_infra.sh --monitoring \\"
    warn "    --swarm-join-worker \\"
    warn "    --swarm-manager-addr=${SWARM_MANAGER_ADDR} \\"
    warn "    --swarm-join-token=<TOKEN>"
    warn ""
    die "Bitte Token manuell übergeben"
  fi
fi

if [[ "$SWARM_ACTION" == "join-manager" && -z "$SWARM_JOIN_TOKEN" ]]; then
  if SWARM_JOIN_TOKEN="$(fetch_swarm_token "$SWARM_MANAGER_ADDR" "manager")"; then
    warn "Manager-Token automatisch vom Manager abgerufen"
  else
    warn "Token-Abruf fehlgeschlagen – Fallback auf manuelle Methode"
    warn "Bitte Token manuell abrufen und übergeben:"
    warn ""
    warn "  ssh ${TARGET_USER}@${SWARM_MANAGER_ADDR%:*} \"docker swarm join-token manager -q\""
    warn ""
    warn "Dann Deploy mit Token wiederholen:"
    warn "  ./deploy_infra.sh --monitoring \\"
    warn "    --swarm-join-manager \\"
    warn "    --swarm-manager-addr=${SWARM_MANAGER_ADDR} \\"
    warn "    --swarm-join-token=<TOKEN>"
    warn ""
    die "Bitte Token manuell übergeben"
  fi
fi

log "Deploy nach ${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}"

# Zielverzeichnis anlegen
ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" \
  "sudo mkdir -p '${TARGET_DIR}' && sudo chown -R '${TARGET_USER}':'${TARGET_USER}' '${TARGET_DIR}'" \
  || die "Remote-Verbindung oder Rechteproblem."

# Dateien übertragen
log "Übertrage Repo via rsync..."
rsync -av --delete \
  --exclude '.git' \
  --exclude '.idea' \
  --exclude '.vscode' \
  ./ "${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}" \
  || die "rsync fehlgeschlagen."

# ====== Remote Postinstall ======
log "Starte Postinstall auf Remote..."

if [[ "$DO_HOTSPOT" -eq 1 ]]; then
  log "🔥 Modus: CORE + HOTSPOT"
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "
    cd '${TARGET_DIR}' &&
    sudo chmod +x postinstall/*.sh &&
    sudo SWARM_ACTION='${SWARM_ACTION}' \
         SWARM_ADVERTISE_ADDR='${SWARM_ADVERTISE_ADDR}' \
         SWARM_MANAGER_ADDR='${SWARM_MANAGER_ADDR}' \
         SWARM_JOIN_TOKEN='${SWARM_JOIN_TOKEN}' \
         ./postinstall/postinstall.sh --hotspot
  " || die "Postinstall (Hotspot) fehlgeschlagen."

elif [[ "$DO_MONITORING" -eq 1 ]]; then
  log "📊 Modus: MONITORING"
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "
    cd '${TARGET_DIR}' &&
    sudo chmod +x postinstall/*.sh &&
    sudo SWARM_ACTION='${SWARM_ACTION}' \
         SWARM_ADVERTISE_ADDR='${SWARM_ADVERTISE_ADDR}' \
         SWARM_MANAGER_ADDR='${SWARM_MANAGER_ADDR}' \
         SWARM_JOIN_TOKEN='${SWARM_JOIN_TOKEN}' \
         ./postinstall/postinstall.sh --monitoring
  " || die "Postinstall (Monitoring) fehlgeschlagen."

else
  log "🧊 Modus: CORE ONLY"
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "
    cd '${TARGET_DIR}' &&
    sudo chmod +x postinstall/*.sh &&
    sudo SWARM_ACTION='${SWARM_ACTION}' \
         SWARM_ADVERTISE_ADDR='${SWARM_ADVERTISE_ADDR}' \
         SWARM_MANAGER_ADDR='${SWARM_MANAGER_ADDR}' \
         SWARM_JOIN_TOKEN='${SWARM_JOIN_TOKEN}' \
         ./postinstall/postinstall.sh --core-only
  " || die "Postinstall (Core) fehlgeschlagen."
fi

log "✅ Deployment abgeschlossen."

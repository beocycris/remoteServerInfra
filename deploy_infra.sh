#!/bin/bash
set -euo pipefail

# ====== Konfiguration ======
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOST="${TARGET_HOST:-10.10.100.162}"
TARGET_DIR="${TARGET_DIR:-/opt/brewery-infra}"

SSH_OPTS="${SSH_OPTS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR }"

# ====== Flags ======
DO_CORE_ONLY=0
DO_HOTSPOT=0
DO_MONITORING=0

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

# ====== Helpers ======
log() { echo -e "🟦 $*"; }
warn() { echo -e "🟨 $*" >&2; }
die() { echo -e "🟥 $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Fehlendes Kommando: $1"; }

# ====== Checks lokal ======
need_cmd rsync
need_cmd ssh

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
    sudo ./postinstall/postinstall.sh --hotspot
  " || die "Postinstall (Hotspot) fehlgeschlagen."

elif [[ "$DO_MONITORING" -eq 1 ]]; then
  log "📊 Modus: MONITORING"
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "
    cd '${TARGET_DIR}' &&
    sudo chmod +x postinstall/*.sh &&
    sudo ./postinstall/postinstall.sh --monitoring
  " || die "Postinstall (Monitoring) fehlgeschlagen."

else
  log "🧊 Modus: CORE ONLY"
  ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "
    cd '${TARGET_DIR}' &&
    sudo chmod +x postinstall/*.sh &&
    sudo ./postinstall/postinstall.sh --core-only
  " || die "Postinstall (Core) fehlgeschlagen."
fi

log "✅ Deployment abgeschlossen."

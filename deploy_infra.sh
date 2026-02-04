#!/bin/bash
set -euo pipefail

# ====== Konfiguration ======
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_HOST="${TARGET_HOST:-192.168.7.1}"
TARGET_DIR="${TARGET_DIR:-/opt/brewery-infra}"

SSH_OPTS="${SSH_OPTS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR }"

# ====== Helpers ======
log() { echo -e "🟦 $*"; }
warn() { echo -e "🟨 $*" >&2; }
die() { echo -e "🟥 $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Fehlendes Kommando: $1"; }

# ====== Checks lokal ======
need_cmd rsync
need_cmd ssh

log "Deploy nach ${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}"

# Zielverzeichnis anlegen (idempotent)
ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "sudo mkdir -p '${TARGET_DIR}' && sudo chown -R '${TARGET_USER}':'${TARGET_USER}' '${TARGET_DIR}'" \
  || die "Remote-Verbindung oder Rechteproblem."

# Dateien übertragen
log "Übertrage Repo via rsync..."
rsync -av --delete \
  --exclude '.git' \
  --exclude '.idea' \
  --exclude '.vscode' \
  ./ "${TARGET_USER}@${TARGET_HOST}:${TARGET_DIR}" \
  || die "rsync fehlgeschlagen."

# Postinstall ausführen
log "Starte Postinstall auf Remote..."
ssh $SSH_OPTS "${TARGET_USER}@${TARGET_HOST}" "cd '${TARGET_DIR}' && sudo chmod +x postinstall/postinstall.sh && sudo ./postinstall/postinstall.sh" \
  || die "Postinstall fehlgeschlagen. Prüfe die Ausgabe oben."

log "✅ Deployment abgeschlossen."
warn "ℹ️ Wenn User-Gruppen geändert wurden (docker-Gruppe): einmal ab-/anmelden oder rebooten."

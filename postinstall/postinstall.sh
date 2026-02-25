#!/bin/bash
set -euo pipefail

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

# ====== Validierung ======
if [[ "$DO_CORE_ONLY" -eq 0 && "$DO_HOTSPOT" -eq 0 && "$DO_MONITORING" -eq 0 ]]; then
  echo "🟥 Bitte mindestens ein Flag angeben:"
  echo "   --core-only | --hotspot | --monitoring"
  exit 1
fi

if [[ "$DO_CORE_ONLY" -eq 1 && "$DO_HOTSPOT" -eq 1 ]]; then
  echo "🟥 --core-only und --hotspot schließen sich aus"
  exit 1
fi

FLAG_DIR="/var/lib/brewery-install"
mkdir -p "$FLAG_DIR"

echo "🟦 Postinstall Orchestrator"

chmod +x \
  ./postinstall/postinstall_core.sh \
  ./postinstall/postinstall_hotspot.sh \
  ./postinstall/postinstall_monitoring.sh \
  ./postinstall/postinstall_swarm.sh

############################################
# MODE: CORE ONLY
############################################
if [[ "$DO_CORE_ONLY" -eq 1 ]]; then
  if [[ ! -f "$FLAG_DIR/core.done" ]]; then
    echo "🟦 Installiere Core"
    sudo ./postinstall/postinstall_core.sh
    touch "$FLAG_DIR/core.done"
  else
    echo "🟨 Core bereits installiert – überspringe"
  fi
  echo "✅ Core-only abgeschlossen"
  exit 0
fi

############################################
# MODE: HOTSPOT ONLY
############################################
if [[ "$DO_HOTSPOT" -eq 1 ]]; then
  [[ -f "$FLAG_DIR/core.done" ]] || {
    echo "🟥 Core fehlt – Hotspot darf nicht initialisiert werden"
    exit 1
  }

  if [[ -f "$FLAG_DIR/hotspot.done" ]]; then
    echo "🟨 Hotspot bereits initialisiert – überspringe"
    exit 0
  fi

  echo "🔥 Initialisiere Hotspot (ohne Core)"
  sudo ./postinstall/postinstall_hotspot.sh
  touch "$FLAG_DIR/hotspot.done"
  echo "✅ Hotspot-Initialisierung abgeschlossen"
  exit 0
fi

############################################
# MODE: MONITORING
############################################
if [[ "$DO_MONITORING" -eq 1 ]]; then
  echo "📊 Installiere Monitoring"
  sudo ./postinstall/postinstall_monitoring.sh
  echo "✅ Monitoring abgeschlossen"
  exit 0
fi

#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;34m🟦 $*\033[0m"; }
err()  { echo -e "\033[1;31m🟥 $*\033[0m"; }

[[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen"; exit 1; }

FLAG_DIR="/var/lib/brewery-install"
MON_FLAG="$FLAG_DIR/monitoring.done"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$FLAG_DIR/core.done" ]] || {
  err "Core nicht installiert – Monitoring abgebrochen"
  exit 1
}

if [[ -f "$MON_FLAG" ]]; then
  log "Monitoring bereits installiert – überspringe"
  exit 0
fi

log "Starte Monitoring-Deployment (Docker Compose)"

cd "$BASE_DIR/monitoring"

# Persistente Daten zentral unter /home/ubuntu/container-data/<container>
mkdir -p \
  /home/ubuntu/container-data/prometheus \
  /home/ubuntu/container-data/grafana \
  /home/ubuntu/container-data/influxdb/data \
  /home/ubuntu/container-data/influxdb/config \
  /home/ubuntu/container-data/telegraf \
  /home/ubuntu/container-data/node-exporter \
  /home/ubuntu/container-data/cadvisor \
  /home/ubuntu/container-data/glances

# Breite Schreibrechte, damit Container-UIDs (grafana/prometheus/influxdb) schreiben können
chmod -R 0777 /home/ubuntu/container-data

# ENV laden (falls vorhanden)
if [[ -f ../env/brewery.env ]]; then
  export $(grep -v '^#' ../env/brewery.env | xargs)
fi

docker compose pull
docker compose up -d

touch "$MON_FLAG"

log "Monitoring erfolgreich gestartet"
echo "📊 Grafana: http://<HOST>:3000"

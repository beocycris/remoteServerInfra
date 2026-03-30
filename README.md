# Brewery Infrastructure

## 📋 Deployment-Anleitung

### Szenario 1: Single-Node (einfaches Deployment)

Für einen einzelnen Host (z.B. lokale VM oder einzelner Server):

```bash
# Repo klonen und SSH-Variablen setzen
git clone <repo-url>
cd remoteServerInfra

export TARGET_USER="ubuntu"
export TARGET_HOST="10.10.100.175"
export TARGET_DIR="/home/ubuntu/brewery-infra"

# Core-Infrastruktur installieren
./deploy_infra.sh --core-only

# Monitoring deployen (optional)
./deploy_infra.sh --monitoring
```

**Resultat:** Docker + Portainer + optional Prometheus/Grafana/InfluxDB auf einem Host.

---

### Szenario 2: Multi-Node Swarm (Monitoring über mehrere Plattformen)

Für verteilte Infrastruktur mit automatischer Metrik-Aggregation über alle Nodes:

#### **Schritt 1: Manager-Node vorbereiten und Swarm initialisieren**

```bash
# Auf deiner lokalen Maschine (Workstation/Mac)
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.10"      # Manager-IP
export TARGET_DIR="/home/ubuntu/brewery-infra"

# Core installieren + Swarm initialisieren
./deploy_infra.sh --core-only

# Dann Monitoring + Swarm Init
./deploy_infra.sh --monitoring \
  --swarm-init \
  --swarm-advertise-addr=192.168.1.10
```

Das Script initialisiert den Swarm. Der Manager ist jetzt ready zum Empfang von Workers und zusätzlichen Managern.

#### **Schritt 2: Worker-Nodes (z.B. Raspberry Pi, zweiter Server) beitreten**

Pro Worker-Host **von deiner lokalen Maschine aus** starten:

```bash
# SSH-Variablen für Worker #1 setzen
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.11"      # Worker-IP 
export TARGET_DIR="/home/ubuntu/brewery-infra"

# 1. Basis-Installation auf Worker
./deploy_infra.sh --core-only

# 2. Monitoring starten + zum Swarm beitreten
# Der Token wird AUTOMATISCH vom Manager abgerufen!
./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377
```

**Für weitere Worker (Worker #2, #3, ...):**

```bash
export TARGET_HOST="192.168.1.12"      # IP des nächsten Workers ändern

./deploy_infra.sh --core-only

./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377
  # Token wird wieder automatisch abgerufen!
```

> **Wichtig:** Die `export TARGET_*` Variablen **müssen vor jedem Deployment gesetzt werden**, damit SSH auf den richtigen Host verbindet!
> 
> **Token-Abruf:** Das Script holt den aktuellen Worker-Token automatisch vom Manager ab – du brauchst `--swarm-join-token` nicht anzugeben!

#### **Schritt 3: Swarm-Cluster prüfen**

SSH in den Manager und prüfe den Swarm-Status:

```bash
ssh ubuntu@192.168.1.10

# Swarm-Übersicht
docker node ls

# Stack-ServiceStatus
docker service ls
docker stack services brewery-monitoring
```

**Erwartetes Resultat:**
```
ID             HOSTNAME          STATUS    AVAILABILITY  MANAGER STATUS
abcd1234...    manager           Ready     Active        Leader
efgh5678...    worker1           Ready     Active        
ijkl9012...    worker2           Ready     Active        
```

Services werden verteilt:
- `prometheus`, `grafana`, `influxdb` → nur auf Manager
- `node-exporter`, `cadvisor`, `glances` → auf **jedem Node** (global)
- `telegraf` → 2 Replikas über Worker verteilt

---

### Szenario 3: Manager-Redundancy (HA-Setup)

Für höhere Verfügbarkeit mit mehreren Managern:

```bash
# SSH-Variablen für zusätzlichen Manager setzen
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.13"      # IP des neuen Managers
export TARGET_DIR="/home/ubuntu/brewery-infra"

./deploy_infra.sh --core-only

./deploy_infra.sh --monitoring \
  --swarm-join-manager \
  --swarm-manager-addr=192.168.1.10:2377
```

Für HA-Setup mindestens **3 Manager-Nodes** empfohlen (Quorum-Mehrheit).

> Der Token wird automatisch vom existierenden Manager abgerufen!

---

### Szenario 4: Hotspot + Swarm (AP-Modus + Monitoring)

Falls ein Node als WLAN-Access-Point + Swarm-Worker laufen soll:

```bash
# SSH-Variablen für Hotspot-Node
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.14"      # Hotspot-Node IP
export TARGET_DIR="/home/ubuntu/brewery-infra"

# 1. Core installieren
./deploy_infra.sh --core-only

# 2. Hotspot initialisieren
./deploy_infra.sh --hotspot

# 3. Monitoring + Swarm-Join
./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377
```

---

## � Swarm Join-Token Verwaltung

### **Automatischer Token-Abruf (mit Fallback)**

Das Deploy-Script versucht den Token zuerst **automatisch** vom Manager abzurufen. Falls das fehlschlägt, wird Fallback auf manuelle Methode:

```bash
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.11"           # Worker-IP
export TARGET_DIR="/home/ubuntu/brewery-infra"

./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377
```

**Normal-Fall (Auto erfolgreich):**
- Script versucht: `ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q"`
- Token wird automatisch verwendet ✅

**Fallback-Fall (Auto fehlgeschlagen, z.B. SSH-Probleme):**
```
🟨 Token-Abruf fehlgeschlagen – Fallback auf manuelle Methode
🟨 Bitte Token manuell abrufen und übergeben:
🟨
🟨   ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q"
🟨
🟨 Dann Deploy mit Token wiederholen:
🟨   ./deploy_infra.sh --monitoring \
🟨     --swarm-join-worker \
🟨     --swarm-manager-addr=192.168.1.10:2377 \
🟨     --swarm-join-token=<TOKEN>
```

### **Manueller Token-Abruf (wenn nötig)**

Falls du den Token selbst benötigst oder als Fallback nutzen willst:

```bash
# SSH zum Manager
ssh ubuntu@192.168.1.10

# Worker-Join-Befehl inkl. Token anzeigen
docker swarm join-token worker

# Nur den Token selbst (ohne Befehl)
docker swarm join-token worker -q

# Manager-Token für HA-Setup
docker swarm join-token manager -q
```

**Beispiel-Output:**
```
SWMTKN-1-3pu6hszjas19xyp7ghgosixsyx97ocja8nj5gvbghosixsyx97ocja8nj5g
```

### **Fallback: Token manuell übergeben**

Falls der auto-Abruf nicht funktioniert, kannst du den Token auch manuell übergeben:

```bash
export TARGET_HOST="192.168.1.11"
export TOKEN=$(ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q")

./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377 \
  --swarm-join-token="$TOKEN"
```

---

### **Grafana öffnen**
- URL: `http://<MANAGER_IP>:3000`
- Benutzer: `admin` / Passwort: `BenFra2020!!`
- Dashboards werden automatisch provisioniert
- Neues Dashboard: **Swarm Cluster Overview**
  - `Nodes: CPU (%)`
  - `Nodes: RAM Used (%)`
  - `Nodes: Running Services (count)`
  - `Services: Running Replicas`
  - `Replica Distribution: Service per Node`

### **Prometheus Queries**
- URL: `http://<MANAGER_IP>:9090`
- Queries auf alle Worker-Nodes verteilt (z.B. `node_cpu_seconds_total{instance=~".*:9100$"}`)

### **InfluxDB**
- URL: `http://<MANAGER_IP>:8086`
- Benutzer: `admin` / Token: `BenFra2020!!`
- Bucket: `brewery` (MQTT-Daten)

### **Services im Swarm verwalten**

```bash
# Im Manager-Node SSH-Session (oder ssh ubuntu@<MANAGER_IP> davor)

# Stack neu deployen (z.B. nach Config-Änderung)
cd brewery-infra/monitoring
docker stack deploy -c docker-stack.yml brewery-monitoring

### **Gesamtes Swarm-Cluster neu starten**

Auf einem **Manager-Node** ausführen (oder per SSH auf den Manager):

```bash
cd brewery-infra
chmod +x restart_swarm_cluster.sh

# Erst prüfen (ohne Reboot)
./restart_swarm_cluster.sh --dry-run

# Danach wirklich ausführen
./restart_swarm_cluster.sh
```

Optional:

```bash
# ohne interaktive Rückfrage
./restart_swarm_cluster.sh --yes

# anderer SSH-User für Worker/Manager-Reboots
TARGET_USER=ubuntu ./restart_swarm_cluster.sh --yes
```

Verhalten des Scripts:
- rebootet zuerst alle Worker
- rebootet den aktuellen Manager zuletzt
- nutzt die Swarm-Node-Adressen aus `docker node inspect`

### **Variante mit Auto-Wait + Healthcheck (von Mac/Workstation)**

Wenn du nach dem Manager-Reboot automatisch warten und direkt prüfen willst:

```bash
cd remoteServerInfra
chmod +x restart_swarm_cluster_remote.sh

# Testlauf ohne Reboot (Manager-IP wird auf Wunsch abgefragt)
TARGET_USER=ubuntu ./restart_swarm_cluster_remote.sh --dry-run

# Echtlauf mit Auto-Wait + Statusprüfung
TARGET_USER=ubuntu TARGET_HOST=10.10.100.166 ./restart_swarm_cluster_remote.sh --yes
```

Diese Variante:
- rebootet Worker zuerst, Manager zuletzt
- fragt auf Wunsch interaktiv nach Manager-IP und welche Worker rebootet werden sollen
- wartet automatisch auf SSH-Reconnect des Managers
- wartet auf `Nodes Ready` + konvergierte Service-Replikas
- zeigt anschließend `docker node ls` und `docker service ls`

# Service skalieren
docker service scale brewery-monitoring_telegraf=3

# Service-Logs
docker service logs brewery-monitoring_telegraf

# Node Labels zum Scheduling setzen
docker node update --label-add region=zone-a worker1
docker node update --label-add region=zone-b worker2

# Anschließend docker-stack.yml anpassen für Placement-Constraints
```

---

## ✅ Deployment-Checklist

- [ ] SSH-Zugriff auf alle Hosts testet
- [ ] `TARGET_USER` und `TARGET_HOST` korrekt gesetzt
- [ ] Docker CE ist auf allen Nodes installierbar
- [ ] Netzwerk: alle Nodes können einander auf Port 2377 (Swarm) erreichen
- [ ] Manager: mindestens Port 2377, 7946 (TCP+UDP), 4789 (UDP) offen
- [ ] Worker: Port 7946, 4789 für Overlay-Netzwerk
- [ ] SSH-Keys für passwordless Login (optional, aber empfohlen)
- [ ] Backup: `./postinstall` Verzeichnis vor Änderungen sichern

---

## 🔧 Troubleshooting & Häufige Probleme

### **Problem: SSH-Timeout**
```bash
# SSH manuell testen
ssh -v ubuntu@192.168.1.10
# Falls erforderlich, SSH-Key konfigurieren
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@192.168.1.10
```

### **Problem: Token-Abruf vom Manager fehlgeschlagen**
```bash
# 1. Prüfe, ob Manager erreichbar ist
ping 192.168.1.10

# 2. Prüfe SSH-Zugriff zum Manager
ssh ubuntu@192.168.1.10 "docker node ls"

# 3. Prüfe, ob Manager im Swarm aktiv ist
ssh ubuntu@192.168.1.10 "docker info | grep 'Swarm: active'"

# 4. Token manuell anzeigen
ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q"

# 5. Falls auto-Abruf immer noch fehlschlägt → Token manuel übergeben
TOKEN=$(ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q")
./deploy_infra.sh --monitoring \
  --swarm-join-worker \
  --swarm-manager-addr=192.168.1.10:2377 \
  --swarm-join-token="$TOKEN"
```

### **Problem: Worker-Node tritt Swarm nicht bei**
```bash
# Auf dem Worker prüfen
ssh ubuntu@192.168.1.11
docker swarm leave --force
# Token erneut abrufen vom Manager
ssh ubuntu@192.168.1.10 docker swarm join-token worker
# Dann Deployment neu starten
```

### **Problem: Services starten nicht im Swarm**
```bash
# Logs prüfen
docker service logs brewery-monitoring_prometheus --follow
docker service ls -q | xargs -I {} docker service ps {} --no-trunc

# Ggf. docker-stack.yml prüfen
cd recording/monitoring
docker stack deploy --compose-file docker-stack.yml --with-registry-auth brewery-monitoring
```

### **Problem: Grafana Datasource zeigt keine Daten**
```bash
# Prometheus-Health prüfen
curl http://192.168.1.10:9090/-/healthy
# InfluxDB erreichbar?
curl http://192.168.1.10:8086/health
# Telegraf Logs
docker service logs brewery-monitoring_telegraf --tail=50
```

---

## Übersicht

Dieses Repository enthält Scripts und Docker-Compose-Konfigurationen zur Orchestrierung der Anwendungs- und Monitoring-Services. Ziel ist eine unkomplizierte Umgebung zum Deployen, Überwachen und Testen der Infrastruktur auf einem oder mehreren Hosts.

**Modi:**
- **Single-Node:** Docker + Portainer (einfaches Setup)
- **Multi-Node Swarm:** Automatische Metrik-Aggregation über alle Nodes mit Replicas
- **Manager-HA:** Mehrere Swarm-Manager für höhere Verfügbarkeit
- **Hotspot-Mode:** Optional WLAN-Access-Point auf einem Node

**Wichtige Bestandteile:**
- `deploy_infra.sh` – Haupt-Deploy-Script mit Swarm-Unterstützung
- `postinstall/*.sh` – Host-Vorbereitung (Core, Monitoring, Hotspot, Swarm)
- `monitoring/docker-stack.yml` – Swarm-kompatible Stack-Definition
- `monitoring/docker-compose.yml` – Standard Docker Compose (Fallback)
- `env/brewery.env` – Umgebungsvariablen

---

## Voraussetzungen ✅

- SSH-Zugriff auf alle Ziel-Hosts
- `rsync` auf lokaler Maschine (für Dateien-Transfer)
- Bash auf allen Hosts
- Tipp: Unter macOS empfiehlt sich die Installation über Docker Desktop; SSH Keys für passwordless Login konfigurieren

---

---

## Schnellstart: Lokal/Single-Node (mit Docker Compose) ⚡

Falls du das System lokal auf einer einzelnen Maschine (ohne remote SSH/Swarm) testen möchtest:

```bash
git clone <repo-url>
cd remoteServerInfra

chmod +x ./deploy_infra.sh

# Core + Monitoring starten
docker compose -f monitoring/docker-compose.yml up -d
```

- Grafana: http://localhost:3000 (Admin / `BenFra2020!!`)
- Prometheus: http://localhost:9090
- InfluxDB: http://localhost:8086

---

## Nützliche Befehle im Betrieb

```bash
# Swarm Status
docker node ls
docker service ls

# Stack neu deployen (nach Config-Änderung)
cd /home/ubuntu/brewery-infra/monitoring
docker stack deploy -c docker-stack.yml brewery-monitoring

# Service-Logs folgen
docker service logs brewery-monitoring_telegraf -f

# Node-Labels für Scheduling
docker node update --label-add region=zone-a <NODE_NAME>

# Service-Replikas ändern
docker service scale brewery-monitoring_telegraf=5
```

---

## 📚 Architektur & Monitoring Details 🔧

Container-Services und deren Rollen:

- **Prometheus** (Manager-only): Scraping & Zeitreihen-DB
- **Grafana** (Manager-only): Visualisierung & Dashboards
- **InfluxDB** (Manager-only): MQTT-Daten-Speicher
- **node-exporter** (global): Hardware-Metriken von jedem Node
- **cAdvisor** (global): Container-Metriken pro Host
- **Glances** (global): System-Monitoring mit Web-UI
- **Telegraf** (2+ Replikas distributed): MQTT-Listener, Metriken-Exporter

**Netzwerk:**
- Overlay-Netzwerk `monitoring` für sichere Service-Kommunikation
- Alle Services können sich per Hostname `<service-name>` erreichen

**Konfigurationen:**
- `monitoring/prometheus/prometheus.yml` – Scrape-Targets
- `monitoring/telegraf/telegraf.conf` – MQTT & InfluxDB Config
- `monitoring/grafana/provisioning/` – Dashboards & Datasources

### Standard-Ports

| Port  | Service        | Zugriff         |
|-------|----------------|----|
| 3000  | Grafana        | Host:3000 |
| 9090  | Prometheus     | Host:9090 |
| 8086  | InfluxDB       | Host:8086 |
| 9273  | Telegraf/Prom  | Host:9273 |
| 9100  | node-exporter  | Nur intern (Service Discovery) |
| 8085  | cAdvisor       | Host:8085 |
| 61028 | Glances        | Host:61028 |

---

## 📝 Quick-Reference: Häufige Deploy-Befehle

```bash
# ========== MANAGER SETUP ==========
export TARGET_USER="ubuntu"
export TARGET_HOST="192.168.1.10"
export TARGET_DIR="/home/ubuntu/brewery-infra"

./deploy_infra.sh --core-only
./deploy_infra.sh --monitoring --swarm-init --swarm-advertise-addr=192.168.1.10

# ========== WORKER SETUP ==========
export TARGET_HOST="192.168.1.11"  # pro Worker ändern

./deploy_infra.sh --core-only
./deploy_infra.sh --monitoring --swarm-join-worker --swarm-manager-addr=192.168.1.10:2377

# ========== SWARM INSPECTION (im Manager) ==========
docker node ls                                    # Alle Nodes anzeigen
docker service ls                                # Services im Swarm
docker stack services brewery-monitoring         # Services im Stack
docker service logs brewery-monitoring_telegraf  # Service-Logs

# ========== STACK VERWALTUNG (im Manager) ==========
cd /home/ubuntu/brewery-infra/monitoring
docker stack deploy -c docker-stack.yml brewery-monitoring  # Stack neu deployen
docker service scale brewery-monitoring_telegraf=3          # Service skalieren

# ========== TOKEN-ABRUF ==========
ssh ubuntu@192.168.1.10 "docker swarm join-token worker -q"   # Worker-Token
ssh ubuntu@192.168.1.10 "docker swarm join-token manager -q"  # Manager-Token
```

---

## Mitwirken (Contributing) 🤝

Pull Requests sind willkommen. Bitte folge dem bestehenden Stil und dokumentiere größere Änderungen im Changelog (oder in einem PR-Description-Template).

---

## Lizenz & Kontakt

Standardmäßig ist keine Lizenz hinterlegt — füge bei Bedarf eine `LICENSE`-Datei hinzu (z.B. MIT).

Bei Fragen: öffne ein Issue oder kontaktiere die Maintainer über das Repository.

---

Viel Erfolg beim Deployen und Monitoring! 🚀

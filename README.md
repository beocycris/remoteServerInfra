# Brewery Infrastructure

## Deployment
```bash
./deploy_infra.sh

```

---

## Übersicht

Dieses Repository enthält Scripts und Docker-Compose-Konfigurationen zur Orchestrierung der Anwendungs- und Monitoring-Services. Ziel ist eine unkomplizierte Umgebung zum Deployen, Überwachen und Testen der Infrastruktur.

Wichtige Bestandteile:

- **Provisioning & Deployment:** `deploy_infra.sh` (Haupt-Deploy-Script)
- **Container-Orchestrierung:** `docker/compose.yml`
- **Umgebungsvariablen:** `env/brewery.env`
- **Monitoring:** `monitoring/docker-compose.yml`, Grafana-Provisioning unter `monitoring/grafana/` und Prometheus-Konfiguration unter `monitoring/prometheus/`
- **Post-Install Schritte:** `postinstall/postinstall.sh`

---

## Voraussetzungen ✅

- Docker und Docker Compose (oder `docker compose`)
- Bash (für die bereitgestellten Shell-Skripte)

Tipp: Unter macOS empfiehlt sich die Installation über Docker Desktop oder Homebrew-Pakete.

---

## Schnellstart (lokal) ⚡

1. Repository klonen:

```bash
git clone <repo-url>
cd remoteServerInfra
```

2. Umgebungsvariablen prüfen und anpassen:

```bash
cp env/brewery.env .env
# oder: bearbeite env/brewery.env direkt
```

3. Infrastruktur deployen:

```bash
chmod +x ./deploy_infra.sh
./deploy_infra.sh
```

Hinweis: Das Script `deploy_infra.sh` startet und konfiguriert die benötigten Container (siehe Script-Inhalt für Details).

4. Monitoring starten (optional getrennt):

```bash
docker compose -f monitoring/docker-compose.yml up -d
```

5. Grafana öffnen (Standard):

- URL: http://localhost:3000
- Provisioned Dashboards & Datasources befinden sich in `monitoring/grafana/provisioning/`

---

## Architektur & Monitoring 🔧

- Prometheus sammelt Metriken (Konfiguration: `monitoring/prometheus/prometheus.yml`).
- Grafana ist via Provisioning vorkonfiguriert (Dashboards, Datasources) unter `monitoring/grafana/provisioning/`.
- Telegraf liest MQTT-Nachrichten und schreibt sie parallel nach InfluxDB sowie als Prometheus-Metriken für Grafana (Konfiguration: `monitoring/telegraf/telegraf.conf`).
- InfluxDB 2 ist für MQTT-Zeitreihendaten integriert und als Grafana-Datasource provisioniert.
- Dashboards sind YAML/JSON-basiert und werden beim Containerstart automatisch geladen.

### Ablageorte auf dem Zielsystem

Standard-Deploy-Pfad ist:

- `/home/ubuntu/brewery-infra`

Typische Ordner je Modus:

- Core/Repository-Dateien: `/home/ubuntu/brewery-infra`
- Monitoring-Compose & Config: `/home/ubuntu/brewery-infra/monitoring`
- Monitoring-Daten zentral je Container unter `/home/ubuntu/container-data`:
	- `/home/ubuntu/container-data/prometheus`
	- `/home/ubuntu/container-data/grafana`
	- `/home/ubuntu/container-data/influxdb/data`
	- `/home/ubuntu/container-data/influxdb/config`
	- `/home/ubuntu/container-data/telegraf`
	- `/home/ubuntu/container-data/node-exporter` (strukturbedingt, optional leer)
	- `/home/ubuntu/container-data/cadvisor` (strukturbedingt, optional leer)
	- `/home/ubuntu/container-data/glances` (strukturbedingt, optional leer)
- Hotspot-Projektdaten: `/home/ubuntu/brewery-infra/hotspot`

Installations-Flags liegen systemweit unter `/var/lib/brewery-install`.
Docker selbst (Engine, Images, Layer) bleibt weiterhin unter dem Standardpfad `/var/lib/docker`.

### MQTT via Telegraf

Der Service `telegraf` ist in `monitoring/docker-compose.yml` integriert und nutzt folgende Variablen:

- `MQTT_BROKER_URL` (Default: `tcp://host.docker.internal:1883`)
- `MQTT_TOPICS` (Default: `brewery/#`)
- `MQTT_QOS` (Default: `0`)
- `MQTT_CLIENT_ID` (Default: `telegraf-brewery`)
- `MQTT_USERNAME` / `MQTT_PASSWORD` (optional)

Nachrichten werden als JSON erwartet (`data_format = "json"`), als Prometheus-Metriken auf Port `9273` exportiert und zusätzlich nach InfluxDB-Bucket `mqtt` geschrieben.

### InfluxDB Zugang

- URL: `http://localhost:8086`
- Benutzer: `admin`
- Passwort: `BenFra2020!!`
- Org: `brewery`
- Bucket: `mqtt`
- Admin Token: `BenFra2020!!`

### Schnellcheck: MQTT → Telegraf → InfluxDB → Grafana

1. Monitoring-Stack starten/neu laden:

```bash
docker compose -f monitoring/docker-compose.yml up -d
```

2. Service-Status prüfen:

```bash
docker compose -f monitoring/docker-compose.yml ps
```

3. Telegraf-Metrics-Endpunkt prüfen (Prometheus-Export):

```bash
curl -s http://localhost:9273/metrics | head
```

4. InfluxDB-Health prüfen:

```bash
curl -s http://localhost:8086/health
```

5. Datenfluss über Logs verifizieren:

```bash
docker compose -f monitoring/docker-compose.yml logs telegraf --tail=100
```

In Grafana unter `Connections -> Data sources` sollten `Prometheus` und `InfluxDB` als verfügbare Datasources sichtbar sein.

---

## Nützliche Scripts

- `deploy_infra.sh` – Haupt-Deploy-Script
- `postinstall/postinstall.sh` – zusätzliche Setup-Schritte
- `monitoring/docker-compose.yml` – startet Prometheus & Grafana

---

## Fehlerbehebung

- Container-Logs prüfen:

```bash
docker compose ps
docker compose logs <service>
```

- Prüfe, ob Ports (z.B. 3000 für Grafana) bereits belegt sind.
- Wenn Dashboards fehlen: prüfe `monitoring/grafana/provisioning/` auf korrekte Pfade und Dateinamen.

---

## Mitwirken (Contributing) 🤝

Pull Requests sind willkommen. Bitte folge dem bestehenden Stil und dokumentiere größere Änderungen im Changelog (oder in einem PR-Description-Template).

---

## Lizenz & Kontakt

Standardmäßig ist keine Lizenz hinterlegt — füge bei Bedarf eine `LICENSE`-Datei hinzu (z.B. MIT).

Bei Fragen: öffne ein Issue oder kontaktiere die Maintainer über das Repository.

---

Viel Erfolg beim Deployen und Monitoring! 🚀

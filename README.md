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
- Dashboards sind YAML/JSON-basiert und werden beim Containerstart automatisch geladen.

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

#!/bin/bash
set -euo pipefail

echo "🍺 Brewery Post-Install startet..."

############################################
# Root-Check
############################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Bitte als root oder mit sudo ausführen."
  exit 1
fi

############################################
# Konfiguration
############################################
SSID="${SSID:-Brewery}"
WPA_PASS="${WPA_PASS:-BenFra2020!}"

WLAN_IF="${WLAN_IF:-wlan0}"
ETH_IF="${ETH_IF:-eth0}"

AP_IP="${AP_IP:-192.168.7.1}"
CIDR="${CIDR:-24}"
DHCP_START="${DHCP_START:-192.168.7.10}"
DHCP_END="${DHCP_END:-192.168.7.50}"

DOCKER_USER="${DOCKER_USER:-${SUDO_USER:-pi}}"
PORTAINER_NAME="${PORTAINER_NAME:-portainer}"
PORTAINER_VOLUME="${PORTAINER_VOLUME:-portainer_data}"

############################################
# Helpers
############################################
log()  { echo -e "🟦 $*"; }
warn() { echo -e "🟨 $*" >&2; }
die()  { echo -e "🟥 $*" >&2; exit 1; }

# optional: soften errors in non-critical steps
soft_fail() {
  local msg="$1"
  shift || true
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "$msg (rc=$rc) – fahre fort"
  fi
  return 0
}

retry() {
  # retry <tries> <sleep_seconds> <command...>
  local tries="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= tries )); then
      return 1
    fi
    warn "Retry $n/$tries für: $* (warte ${sleep_s}s)"
    sleep "$sleep_s"
    ((n++))
  done
  return 0
}

pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

apt_install() {
  local pkg="$1"
  if pkg_installed "$pkg"; then
    log "✅ Paket bereits installiert: $pkg"
  else
    log "📦 Installiere Paket: $pkg"
    apt install -y "$pkg"
  fi
}

service_exists() {
  systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

safe_systemctl() {
  # safe_systemctl <action> <service> [critical|optional]
  local action="$1"
  local svc="$2"
  local mode="${3:-critical}"

  if service_exists "$svc"; then
    if [[ "$mode" == "optional" ]]; then
      soft_fail "⚠️ systemctl $action $svc fehlgeschlagen" systemctl "$action" "$svc"
    else
      systemctl "$action" "$svc"
    fi
  else
    warn "Service nicht vorhanden: $svc (übersprungen)"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Fehlendes Kommando: $1"
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

wait_for_network() {
  # optional: helps with fresh installs; does not hard-fail
  log "🌐 Prüfe Netzwerk..."
  for _ in {1..10}; do
    if ping -c1 1.1.1.1 >/dev/null 2>&1; then
      log "✅ Netzwerk erreichbar"
      return 0
    fi
    sleep 2
  done
  warn "⚠️ Netzwerk nicht sicher erreichbar – fahre fort (apt kann dennoch funktionieren)."
  return 0
}

############################################
# OS-Erkennung
############################################
source /etc/os-release
ARCH=$(dpkg --print-architecture)

if [[ "$ID" == "ubuntu" ]]; then
  DISTRO="jammy" # stabiler Fallback für Ubuntu 24/25
elif [[ "$ID" == "debian" || "$ID" == "raspbian" ]]; then
  require_cmd lsb_release
  DISTRO=$(lsb_release -cs)
else
  die "Nicht unterstütztes OS: $ID"
fi

log "🧠 OS: $ID $VERSION_ID | Repo: $DISTRO | Arch: $ARCH"

############################################
# Basispakete (kritisch)
############################################
wait_for_network

log "📦 apt update (mit retry)..."
retry 3 5 apt update || die "apt update fehlgeschlagen."

# Minimal: Dinge fürs Hotspot-Setup + persistentes iptables
for p in ca-certificates curl gnupg lsb-release uidmap hostapd dnsmasq iptables-persistent; do
  apt_install "$p"
done

# hostapd enable (kritisch)
safe_systemctl unmask hostapd.service optional
safe_systemctl enable hostapd.service critical

############################################
# WLAN statisch (idempotent)
############################################
log "📶 Konfiguriere WLAN statisch (dhcpcd.conf)..."

# Manche Systeme nutzen kein dhcpcd (z.B. Ubuntu Server via netplan).
# Wir nutzen dhcpcd nur, wenn es existiert – sonst warnen wir und fahren fort.
if service_exists dhcpcd.service || command -v dhcpcd >/dev/null 2>&1; then
  if [[ -f /etc/dhcpcd.conf ]]; then
    if ! grep -q "Brewery Hotspot" /etc/dhcpcd.conf; then
      cat <<EOF >> /etc/dhcpcd.conf

# Brewery Hotspot
interface $WLAN_IF
    static ip_address=$AP_IP/$CIDR
    nohook wpa_supplicant
EOF
      log "✅ dhcpcd.conf ergänzt"
    else
      log "✅ dhcpcd.conf bereits konfiguriert"
    fi
  else
    warn "⚠️ /etc/dhcpcd.conf nicht gefunden – auf diesem OS ggf. netplan/networkd. Hotspot-Teil ggf. anpassen."
  fi
else
  warn "⚠️ dhcpcd nicht vorhanden – auf Ubuntu Server häufig netplan. Hotspot-Teil ggf. anpassen."
fi

############################################
# hostapd (kritisch)
############################################
log "📡 Schreibe hostapd.conf..."
cat <<EOF > /etc/hostapd/hostapd.conf
interface=$WLAN_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
ieee80211n=1
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WPA_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# /etc/default/hostapd existiert nicht überall; optional
if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
  warn "⚠️ /etc/default/hostapd fehlt – auf deinem OS kann hostapd die config via service override bekommen (falls nötig)."
fi

############################################
# dnsmasq (kritisch)
############################################
log "📦 Konfiguriere dnsmasq (DHCP)..."
if [[ -f /etc/dnsmasq.conf && ! -f /etc/dnsmasq.conf.orig ]]; then
  cp -a /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
fi

cat <<EOF > /etc/dnsmasq.conf
interface=$WLAN_IF
dhcp-range=$DHCP_START,$DHCP_END,12h
domain-needed
bogus-priv
server=1.1.1.1
server=8.8.8.8
EOF

############################################
# Routing & NAT (kritisch)
############################################
log "🔁 Aktiviere IP-Forwarding..."
# Setze dauerhaft & sofort
if grep -q '^#net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
elif ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null

log "🌍 Setze iptables NAT/Forward Regeln (idempotent)..."
iptables -t nat -C POSTROUTING -o "$ETH_IF" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$ETH_IF" -j MASQUERADE

iptables -C FORWARD -i "$ETH_IF" -o "$WLAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i "$ETH_IF" -o "$WLAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -C FORWARD -i "$WLAN_IF" -o "$ETH_IF" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i "$WLAN_IF" -o "$ETH_IF" -j ACCEPT

soft_fail "⚠️ netfilter-persistent save fehlgeschlagen" netfilter-persistent save

############################################
# Docker installieren (kritisch)
############################################
log "🐳 Installiere Docker (idempotent)..."

mkdir -p /etc/apt/keyrings

# GPG nur anlegen, wenn nicht vorhanden
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  log "🔐 Docker GPG-Key..."
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
else
  log "✅ Docker GPG-Key bereits vorhanden"
fi

# Repo nur schreiben, wenn Inhalt abweicht/fehlt
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
DOCKER_LINE="deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $DISTRO stable"
if [[ ! -f "$DOCKER_LIST" ]] || ! grep -qF "$DOCKER_LINE" "$DOCKER_LIST"; then
  log "📚 Docker Repo konfigurieren..."
  echo "$DOCKER_LINE" > "$DOCKER_LIST"
else
  log "✅ Docker Repo bereits konfiguriert"
fi

retry 3 5 apt update || die "apt update nach Docker-Repo fehlgeschlagen."

for p in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  apt_install "$p"
done

safe_systemctl enable docker.service critical
safe_systemctl start docker.service critical

# usermod optional (kann beim root-run SUDO_USER leer sein)
if id "$DOCKER_USER" >/dev/null 2>&1; then
  if id -nG "$DOCKER_USER" | grep -qw docker; then
    log "✅ User '$DOCKER_USER' ist bereits in der docker-Gruppe"
  else
    log "👤 Füge User '$DOCKER_USER' zur docker-Gruppe hinzu..."
    soft_fail "⚠️ usermod fehlgeschlagen" usermod -aG docker "$DOCKER_USER"
  fi
else
  warn "⚠️ User '$DOCKER_USER' nicht gefunden – docker Gruppen-Zuordnung übersprungen"
fi

############################################
# Portainer (optional: läuft, wenn Docker ok)
############################################
log "🧭 Portainer Setup..."
if docker_ready; then
  docker volume inspect "$PORTAINER_VOLUME" >/dev/null 2>&1 || docker volume create "$PORTAINER_VOLUME" >/dev/null

  if docker ps -a --format '{{.Names}}' | grep -qx "$PORTAINER_NAME"; then
    log "✅ Portainer Container existiert bereits"
    # optional: sicherstellen, dass er läuft
    soft_fail "⚠️ Portainer start fehlgeschlagen" docker start "$PORTAINER_NAME"
  else
    log "📦 Starte Portainer Container..."
    docker run -d \
      --name "$PORTAINER_NAME" \
      --restart=always \
      -p 9000:9000 \
      -p 9443:9443 \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$PORTAINER_VOLUME":/data \
      portainer/portainer-ce:latest >/dev/null
  fi
else
  warn "⚠️ Docker nicht bereit – Portainer übersprungen"
fi

############################################
# Hotspot Dienste (kritisch)
############################################
log "🔄 Starte Hotspot-Dienste neu..."
# dhcpcd existiert nicht überall -> optional
safe_systemctl restart dhcpcd.service optional
safe_systemctl restart dnsmasq.service critical
safe_systemctl restart hostapd.service critical

############################################
# Abschluss
############################################
echo ""
echo "✅ Brewery Post-Install abgeschlossen!"
echo "📶 Hotspot: $SSID"
echo "🌐 Gateway: $AP_IP"
echo "🐳 Portainer: http://$AP_IP:9000  | https://$AP_IP:9443"
echo ""
echo "ℹ️ Monitoring (Prometheus/Grafana/Glances) wird über 'monitoring/docker-compose.yml' gestartet."
echo "➡️ Reboot empfohlen (besonders nach Gruppenrechten / WLAN-Land Einstellung)."

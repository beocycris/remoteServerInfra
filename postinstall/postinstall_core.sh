#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;34m🟦 $*\033[0m"; }
ok()   { echo -e "\033[1;32m✅ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $*\033[0m"; }
err()  { echo -e "\033[1;31m🟥 $*\033[0m"; }

[[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen"; exit 1; }

# Konfig
DOCKER_USER="${SUDO_USER:-ubuntu}"

# OS-Erkennung
source /etc/os-release
ARCH="$(dpkg --print-architecture)"
ID_OK=false
[[ "$ID" == "ubuntu" || "$ID" == "debian" || "$ID" == "raspbian" ]] && ID_OK=true
$ID_OK || { err "Nicht unterstütztes OS: $ID"; exit 1; }

DISTRO="$VERSION_CODENAME"
log "OS: $ID $DISTRO ($ARCH)"

############################################
# WICHTIG: NetworkManager NICHT deaktivieren!
############################################
log "Netzwerk: NetworkManager bleibt aktiv (LAN/SSH-sicher)"
# Optional: nur Info ausgeben
systemctl is-active --quiet NetworkManager && ok "NetworkManager läuft" || warn "NetworkManager läuft nicht (ok, wenn statisch konfiguriert)"

############################################
# Basispakete
############################################
log "Installiere Basispakete"
apt update
apt install -y \
  hostapd dnsmasq iptables-persistent \
  rfkill iw \
  ca-certificates curl gnupg lsb-release

############################################
# Forwarding dauerhaft
############################################
log "Aktiviere IP Forwarding"
sysctl -w net.ipv4.ip_forward=1
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

############################################
# Docker Repo Cleanup (Signed-By Fix!)
############################################
log "Docker Repo & Key Cleanup"
rm -f /etc/apt/sources.list.d/docker*.list
rm -f /etc/apt/keyrings/docker.gpg
rm -f /etc/apt/keyrings/docker.asc
sed -i '/download\.docker\.com/d' /etc/apt/sources.list || true

############################################
# Docker CE Installation
############################################
log "Installiere Docker CE"
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
 | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $DISTRO stable" \
> /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl restart docker

############################################
# Docker User Rechte
############################################
log "Setze Docker-Berechtigungen für $DOCKER_USER"
if ! id -nG "$DOCKER_USER" | grep -qw docker; then
  usermod -aG docker "$DOCKER_USER"
  warn "User $DOCKER_USER zur docker-Gruppe hinzugefügt – Ab-/Anmelden erforderlich"
fi
############################################
# Portainer
############################################
log "Starte Portainer"
docker volume create portainer_data >/dev/null 2>&1 || true

docker ps -a --format '{{.Names}}' | grep -q '^portainer$' || \
docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

ok "Core-Postinstall abgeschlossen (LAN/SSH wurde nicht verändert)"
mkdir -p /var/lib/brewery-install
touch /var/lib/brewery-install/core.done

sudo reboot now
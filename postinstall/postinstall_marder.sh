#!/bin/bash
set -euo pipefail

############################################
# KONFIGURATION
############################################
SSID="Brewery"
WPA_PASS="BenFra2020!"

WLAN_IF="wlan0"
LAN_IF="eth0"

# WLAN-Netz
WLAN_IP="192.168.7.1"
WLAN_CIDR="24"
WLAN_SUBNET="192.168.7.0/24"
WLAN_DHCP_START="192.168.7.10"
WLAN_DHCP_END="192.168.7.50"

# LAN-Netz
LAN_IP="10.10.100.1"
LAN_CIDR="24"
LAN_SUBNET="10.10.100.0/24"
LAN_DHCP_START="10.10.100.10"
LAN_DHCP_END="10.10.100.50"

BASE_DIR="/usr/local/sbin"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
START_SCRIPT="/usr/local/sbin/brewery-hotspot-start.sh"
SERVICE_FILE="/etc/systemd/system/brewery-hotspot.service"
NM_UNMANAGED_CONF="/etc/NetworkManager/conf.d/99-brewery-unmanaged.conf"
SYSCTL_CONF="/etc/sysctl.d/99-brewery-router.conf"

############################################
# ROOT CHECK
############################################
[[ $EUID -eq 0 ]] || { echo "🟥 Bitte mit sudo ausführen"; exit 1; }

echo "🟦 Brewery Router Setup startet"

############################################
# PAKETE
############################################
echo "🟦 Installiere benötigte Pakete"
apt update
apt install -y hostapd dnsmasq iptables

############################################
# VERZEICHNIS
############################################
mkdir -p "$BASE_DIR"
mkdir -p /etc/NetworkManager/conf.d
mkdir -p /var/lib/misc

############################################
# NetworkManager: eth0 + wlan0 nicht verwalten
############################################
echo "🟦 Konfiguriere NetworkManager unmanaged-devices"
cat > "$NM_UNMANAGED_CONF" <<EOF
[keyfile]
unmanaged-devices=interface-name:${WLAN_IF};interface-name:${LAN_IF}
EOF

############################################
# hostapd.conf
############################################
echo "🟦 Erzeuge hostapd.conf"
cat >"$HOSTAPD_CONF" <<EOF
interface=${WLAN_IF}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=1
country_code=DE
ieee80211d=1
wmm_enabled=1
auth_algs=1
ap_max_inactivity=30
disassoc_low_ack=1
skip_inactivity_poll=1
max_num_sta=50
wpa=2
wpa_passphrase=${WPA_PASS}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

############################################
# hostapd default file setzen
############################################
echo "🟦 Konfiguriere hostapd Default-Datei"
if [[ -f /etc/default/hostapd ]]; then
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
    cat >/etc/default/hostapd <<EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF
fi

############################################
# dnsmasq.conf für WLAN + LAN
############################################
echo "🟦 Erzeuge dnsmasq.conf"
cat >"$DNSMASQ_CONF" <<EOF
bind-interfaces

# WLAN
interface=${WLAN_IF}
dhcp-range=${WLAN_IF},${WLAN_DHCP_START},${WLAN_DHCP_END},255.255.255.0,12h
dhcp-option=${WLAN_IF},3,${WLAN_IP}
dhcp-option=${WLAN_IF},6,1.1.1.1,8.8.8.8

# LAN
interface=${LAN_IF}
dhcp-range=${LAN_IF},${LAN_DHCP_START},${LAN_DHCP_END},255.255.255.0,12h
dhcp-option=${LAN_IF},3,${LAN_IP}
dhcp-option=${LAN_IF},6,1.1.1.1,8.8.8.8

dhcp-authoritative
log-dhcp
EOF

############################################
# IP Forwarding persistent
############################################
echo "🟦 Aktiviere IPv4 Forwarding persistent"
cat >"$SYSCTL_CONF" <<EOF
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null

############################################
# START-SKRIPT
############################################
echo "🟦 Erzeuge Startskript"
cat >"$START_SCRIPT" <<EOF
#!/bin/bash
set -euo pipefail

WLAN_IF="${WLAN_IF}"
LAN_IF="${LAN_IF}"

WLAN_IP="${WLAN_IP}"
WLAN_CIDR="${WLAN_CIDR}"

LAN_IP="${LAN_IP}"
LAN_CIDR="${LAN_CIDR}"

HOSTAPD_CONF="${HOSTAPD_CONF}"
DNSMASQ_CONF="${DNSMASQ_CONF}"

echo "[brewery-router] start"

# WLAN unblock
rfkill unblock wifi || true
sleep 1

# Interfaces hochfahren
ip link set "\$WLAN_IF" up || true
ip link set "\$LAN_IF" up || true

# Vorhandene IPs entfernen
ip addr flush dev "\$WLAN_IF" || true
ip addr flush dev "\$LAN_IF" || true

# Statische IPs setzen
ip addr add "\$WLAN_IP/\$WLAN_CIDR" dev "\$WLAN_IF"
ip addr add "\$LAN_IP/\$LAN_CIDR" dev "\$LAN_IF"

# Alte Prozesse entfernen
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
sleep 1

# Lease-Datei sicherstellen
install -d -m 0755 /var/lib/misc
touch /var/lib/misc/dnsmasq.leases
chmod 0644 /var/lib/misc/dnsmasq.leases

# Forwarding aktivieren
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Firewall-Regeln für Routing zwischen LAN und WLAN
iptables -C FORWARD -i "\$WLAN_IF" -o "\$LAN_IF" -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -i "\$WLAN_IF" -o "\$LAN_IF" -j ACCEPT

iptables -C FORWARD -i "\$LAN_IF" -o "\$WLAN_IF" -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 2 -i "\$LAN_IF" -o "\$WLAN_IF" -j ACCEPT

# Optional: lokale Kommunikation der Netze sicherstellen
iptables -C INPUT -i "\$WLAN_IF" -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -i "\$WLAN_IF" -j ACCEPT

iptables -C INPUT -i "\$LAN_IF" -j ACCEPT 2>/dev/null || \
iptables -I INPUT 2 -i "\$LAN_IF" -j ACCEPT

echo "[brewery-router] starte hostapd"
/usr/sbin/hostapd "\$HOSTAPD_CONF" >/var/log/hostapd-brewery.log 2>&1 &
sleep 2

echo "[brewery-router] starte dnsmasq"
/usr/sbin/dnsmasq --conf-file="\$DNSMASQ_CONF"

echo "[brewery-router] ready"
EOF

chmod +x "$START_SCRIPT"

############################################
# systemd SERVICE
############################################
echo "🟦 Erzeuge systemd Service"
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Brewery Router (WLAN AP + LAN DHCP)
After=network-online.target NetworkManager.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${START_SCRIPT}
ExecStop=/bin/bash -c 'pkill hostapd || true; pkill dnsmasq || true'
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

############################################
# Dienste vorbereiten
############################################
echo "🟦 Deaktiviere Standard-dnsmasq/hostapd Dienste"
systemctl disable dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop hostapd 2>/dev/null || true

############################################
# systemd reload + enable
############################################
echo "🟦 Aktiviere Brewery Router Service"
systemctl daemon-reload
systemctl restart NetworkManager
systemctl enable brewery-hotspot.service

echo
echo "✅ Installation abgeschlossen"
echo
echo "➡️ Starte jetzt mit:"
echo "   sudo systemctl start brewery-hotspot"
echo
echo "➡️ Status prüfen mit:"
echo "   systemctl status brewery-hotspot"
echo
echo "➡️ Logs prüfen mit:"
echo "   journalctl -u brewery-hotspot -b"
echo "   cat /var/log/hostapd-brewery.log"
echo
echo "➡️ Erwartete Netze:"
echo "   WLAN: ${WLAN_SUBNET}  Gateway ${WLAN_IP}"
echo "   LAN : ${LAN_SUBNET}  Gateway ${LAN_IP}"
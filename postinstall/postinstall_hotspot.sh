#!/bin/bash
set -euo pipefail

############################################
# KONFIGURATION
############################################
SSID="Brewery"
WPA_PASS="BenFra2020!"

WLAN_IF="wlan0"
LAN_IF="eth0"

AP_IP="192.168.7.1"
CIDR="24"
SUBNET="192.168.7.0/24"

BASE_DIR="/opt/brewery-infra/hotspot"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"
START_SCRIPT="$BASE_DIR/start-hotspot.sh"
SERVICE_FILE="/etc/systemd/system/brewery-hotspot.service"

############################################
# ROOT CHECK
############################################
[[ $EUID -eq 0 ]] || { echo "🟥 Bitte mit sudo ausführen"; exit 1; }

echo "🟦 Brewery Hotspot Setup startet"

############################################
# VERZEICHNIS
############################################
mkdir -p "$BASE_DIR"

############################################
# hostapd.conf
############################################
echo "🟦 Erzeuge hostapd.conf"
cat >"$HOSTAPD_CONF" <<EOF
interface=$WLAN_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=1
country_code=DE
ieee80211d=1
wmm_enabled=1
auth_algs=1

wpa=2
wpa_passphrase=$WPA_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

############################################
# dnsmasq.conf
############################################
echo "🟦 Erzeuge dnsmasq.conf"
cat >"$DNSMASQ_CONF" <<EOF
interface=$WLAN_IF
bind-interfaces

dhcp-range=192.168.7.10,192.168.7.50,255.255.255.0,12h
dhcp-option=3,$AP_IP
dhcp-option=6,1.1.1.1,8.8.8.8

dhcp-authoritative
log-dhcp
EOF

############################################
# START-SKRIPT (exakt dein funktionierender Ablauf)
############################################
echo "🟦 Erzeuge Startskript"
cat >"$START_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail

WLAN_IF="wlan0"
LAN_IF="eth0"
AP_IP="192.168.7.1"
CIDR="24"
SUBNET="192.168.7.0/24"

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DNSMASQ_CONF="/etc/dnsmasq.conf"

echo "[brewery-hotspot] start"

# 1) WLAN unblock (ESSENZIELL nach Boot!)
rfkill unblock wifi || true
sleep 1

# 2) Interface hoch + IP setzen
ip link set "$WLAN_IF" up || true
ip addr flush dev "$WLAN_IF" || true
ip addr add "$AP_IP/$CIDR" dev "$WLAN_IF"

# 3) alte Prozesse entfernen
pkill hostapd 2>/dev/null || true
pkill dnsmasq 2>/dev/null || true
sleep 1

# 4) hostapd (SSID sichtbar)
echo "[brewery-hotspot] hostapd"
/usr/sbin/hostapd "$HOSTAPD_CONF" >/var/log/hostapd-brewery.log 2>&1 &
sleep 2

# 5) dnsmasq (DHCP)
echo "[brewery-hotspot] dnsmasq"
install -d -m 0755 /var/lib/misc
touch /var/lib/misc/dnsmasq.leases
chmod 0644 /var/lib/misc/dnsmasq.leases

/usr/sbin/dnsmasq --conf-file="$DNSMASQ_CONF"

# 6) Forwarding + NAT (Docker-sicher)
sysctl -w net.ipv4.ip_forward=1 >/dev/null

iptables -C FORWARD -i "$WLAN_IF" -o "$LAN_IF" -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -i "$WLAN_IF" -o "$LAN_IF" -j ACCEPT

iptables -C FORWARD -i "$LAN_IF" -o "$WLAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 2 -i "$LAN_IF" -o "$WLAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

iptables -t nat -C POSTROUTING -s "$SUBNET" -o "$LAN_IF" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$LAN_IF" -j MASQUERADE

echo "[brewery-hotspot] ready"
EOF

chmod +x "$START_SCRIPT"

############################################
# systemd SERVICE (korrekt für diesen Ablauf)
############################################
echo "🟦 Erzeuge systemd Service"
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Brewery WLAN Hotspot
After=network.target docker.service
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$START_SCRIPT

[Install]
WantedBy=multi-user.target
EOF

############################################
# systemd aktivieren
############################################
echo "🟦 Aktiviere Service"
systemctl daemon-reload
systemctl enable brewery-hotspot.service

echo
echo "✅ Installation abgeschlossen"
echo "➡️ Starte Hotspot jetzt mit:"
echo "   sudo systemctl start brewery-hotspot"
echo "➡️ Oder rebooten"
echo  "es muss jedes mal das Skript sudo /usr/local/sbin/brewery-hotspot-start.sh ausgeführt werden, damit der Hotspot auch nach einem Reboot wieder läuft"
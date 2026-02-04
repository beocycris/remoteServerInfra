#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;34m🟦 $*\033[0m"; }
ok()   { echo -e "\033[1;32m✅ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠️  $*\033[0m"; }
err()  { echo -e "\033[1;31m🟥 $*\033[0m"; }

[[ $EUID -eq 0 ]] || { err "Bitte mit sudo ausführen"; exit 1; }

FLAG_DIR="/var/lib/brewery-install"

[[ -f "$FLAG_DIR/core.done" ]] || {
  err "Core fehlt – Hotspot abgebrochen"
  exit 1
}

[[ ! -f "$FLAG_DIR/hotspot.done" ]] || {
  warn "Hotspot bereits aktiv – überspringe"
  exit 0
}

# SSH-Schutz: niemals über wlan0
if ip route get 1.1.1.1 | grep -q 'dev wlan0'; then
  err "SSH läuft über wlan0 – Abbruch"
  exit 1
fi

############################################
# Konfiguration
############################################
SSID="Brewery"
WPA_PASS="BenFra2020!"

WLAN_IF="wlan0"
ETH_IF="eth0"

AP_IP="192.168.7.1"
CIDR="24"
DHCP_START="192.168.7.10"
DHCP_END="192.168.7.50"

log "Hotspot-Setup (Runtime, SSH-sicher)"

############################################
# wlan0 aus NetworkManager lösen
############################################
if systemctl is-active --quiet NetworkManager; then
  nmcli device set "$WLAN_IF" managed no || true
  ok "wlan0 aus NetworkManager gelöst"
fi

############################################
# WLAN vorbereiten
############################################
rfkill unblock all || true
ip link set "$WLAN_IF" down || true
sleep 1

iw dev "$WLAN_IF" set type __ap || true

ip addr flush dev "$WLAN_IF"
ip addr add "$AP_IP/$CIDR" dev "$WLAN_IF"
ip link set "$WLAN_IF" up

############################################
# Warten bis wlan0 wirklich bereit ist
############################################
log "Warte auf wlan0"
for i in {1..15}; do
  ip link show "$WLAN_IF" | grep -q "state UP" && break
  sleep 1
done

############################################
# hostapd config
############################################
log "Schreibe hostapd.conf"
cat >/etc/hostapd/hostapd.conf <<EOF
interface=$WLAN_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=1
country_code=DE
ieee80211d=1
wmm_enabled=1
wpa=2
wpa_passphrase=$WPA_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

############################################
# dnsmasq config
############################################
log "Schreibe dnsmasq.conf"
cat >/etc/dnsmasq.conf <<EOF
interface=$WLAN_IF
dhcp-range=$DHCP_START,$DHCP_END,12h
domain-needed
bogus-priv
server=1.1.1.1
server=8.8.8.8
EOF

############################################
# NAT
############################################
log "Aktiviere NAT"
sysctl -w net.ipv4.ip_forward=1

iptables -t nat -C POSTROUTING -o "$ETH_IF" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$ETH_IF" -j MASQUERADE

iptables -C FORWARD -i "$WLAN_IF" -o "$ETH_IF" -j ACCEPT 2>/dev/null || \
iptables -A FORWARD -i "$WLAN_IF" -o "$ETH_IF" -j ACCEPT

############################################
# dnsmasq DIREKT starten
############################################
log "Starte dnsmasq (direkt)"
pkill dnsmasq || true
/usr/sbin/dnsmasq --conf-file=/etc/dnsmasq.conf </dev/null >/dev/null 2>&1 &

############################################
# hostapd DIREKT starten
############################################
log "Starte hostapd (direkt)"
pkill hostapd || true
/usr/sbin/hostapd /etc/hostapd/hostapd.conf </dev/null >/dev/null 2>&1 &

############################################
# Abschluss
############################################
touch "$FLAG_DIR/hotspot.done"

ok "Hotspot aktiv"
echo "📶 WLAN: $SSID"
echo "🌐 Gateway: $AP_IP"
echo "ℹ️ Runtime-Hotspot aktiv – kein Reboot!"

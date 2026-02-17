#!/usr/bin/env bash

# For a given interface and an IP/Mask fixes the IP of the interface to that using also enables autoconnect  
# JavierRibaldelRío 
# H11

set -e

# ==============================
# Usage check
# ==============================

if [ "$#" -ne 2 ]; then
    echo "Usage: sudo $0 <interface> <ip/mask>"
    echo "Example: sudo $0 eth0 192.168.0.1/24"
    exit 1
fi

INTERFACE="$1"
IPADDR="$2"
CONN_NAME="${INTERFACE}-static"

# ==============================
# Root check
# ==============================
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

# ==============================
# Check NetworkManager
# ==============================

if ! systemctl is-active --quiet NetworkManager; then
    echo "Error: NetworkManager is not running."
    exit 1
fi

# ==============================
# Check interface exists
# ==============================

if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    echo "Error: Interface $INTERFACE does not exist."
    exit 1
fi

echo "Configuring $INTERFACE with static IP $IPADDR..."

# ==============================
# Delete existing connections on this interface
# ==============================

nmcli -t -f NAME,DEVICE connection show | grep ":$INTERFACE$" | cut -d: -f1 | while read -r name; do
    echo "Removing existing connection: $name"
    nmcli connection delete "$name"
done

# ==============================
# Create new static connection
# ==============================

nmcli connection add \
    type ethernet \
    ifname "$INTERFACE" \
    con-name "$CONN_NAME" \
    ipv4.method manual \
    ipv4.addresses "$IPADDR" \
    ipv4.never-default yes \
    connection.autoconnect yes \
    connection.wait-device-timeout 0

# ==============================
# Activate connection
# ==============================

nmcli connection up "$CONN_NAME"

echo "Done."
echo "$INTERFACE is now permanently configured as $IPADDR"

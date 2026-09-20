#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img=${DIAG_IMG:-$here/../../images/diag-willow/boot-diag-willow.img}
export PATH="$HOME/.local/opt/platform-tools:$PATH"
MAC=02:00:00:00:42:01        # host side of the RNDIS gadget (init: host_addr)
PHONE=172.16.42.1

(cd "$(dirname "$img")" && sha256sum -c "$here/SHA256SUMS")
[ "$(fastboot getvar unlocked 2>&1 | head -1)" = "unlocked: yes" ] || { echo "bootloader is still locked -- stop"; exit 1; }
[ "$(fastboot getvar product 2>&1 | head -1)" = "product: willow" ] || { echo "not a willow -- stop"; exit 1; }
fastboot boot "$img"

echo "Booted. Watch the phone screen. Waiting for the RNDIS interface ($MAC)..."
find_if() { for d in /sys/class/net/*; do [ "$(cat "$d/address" 2>/dev/null)" = "$MAC" ] && { basename "$d"; return; }; done; }
ifc=; for _ in $(seq 60); do ifc=$(find_if); [ -n "$ifc" ] && break; sleep 0.5; done
if [ -z "$ifc" ]; then
  echo "No RNDIS interface after 30 s. Check the phone screen and the cable/port."
  echo "If the screen is frozen or black: hard hang. Hold Power ~10 s (hardware reset);"
  echo "the phone returns to MIUI because nothing was flashed."
  exit 2
fi
echo "interface $ifc: operstate=$(cat /sys/class/net/$ifc/operstate)"
have_ip() { ip -4 -o addr show dev "$ifc" | grep -q 'inet 172\.16\.42\.'; }
for _ in $(seq 40); do have_ip && break; sleep 0.5; done
if have_ip; then
  echo "$ifc: $(ip -4 -o addr show dev "$ifc" | awk '{print $4}')"
else
  echo "$ifc has no 172.16.42.x address after 20 s (NetworkManager did not pick DHCP up). Run yourself:"
  echo "  nmcli con add type ethernet ifname $ifc con-name willow-diag ipv4.method manual ipv4.addresses 172.16.42.2/24 && nmcli con up willow-diag"
  echo "  or: sudo ip addr add 172.16.42.2/24 dev $ifc && sudo ip link set $ifc up"
fi
echo
echo "Then:"
echo "  curl -s http://$PHONE/report.txt ; curl -s http://$PHONE/dmesg.txt > dmesg-willow.txt ; telnet $PHONE"
echo "  IPv6 fallback: telnet fe80::ff:fe00:4202%$ifc"
echo "Leave with 'reboot -f' in the telnet shell (back to MIUI)."
echo "Hard hang (frozen screen, no network): hold Power ~10 s = hardware reset; returns to MIUI, nothing was flashed."

#!/usr/bin/env bash
# Rechsteiner Cyber Check - Demo-Labor: Wazuh-Server (laeuft IN der VM rcc-wazuh)
# Aufruf in der VM:  bash 02-server-wazuh.sh
set -euo pipefail

echo "== 1/3 Feste IP im internen Netz (10.10.10.10) =="
EXT=$(ip route show default | awk '{print $5}' | head -1)
INT=$(ls /sys/class/net | grep -v -E '^(lo|docker.*|br-.*|veth.*)$' | grep -v "^${EXT}$" | head -1 || true)
if [ -z "${INT}" ]; then
  echo "Zweite Netzwerkkarte nicht gefunden. VM-Einstellungen pruefen (Adapter 2 = Internes Netzwerk 'rcc-buero')." >&2
  exit 1
fi
echo "Externe Karte: ${EXT}, interne Karte: ${INT}"
sudo tee /etc/netplan/60-buero.yaml >/dev/null <<EOF
network:
  version: 2
  ethernets:
    ${INT}:
      dhcp4: false
      addresses: [10.10.10.10/24]
EOF
sudo chmod 600 /etc/netplan/60-buero.yaml
sudo netplan apply
ip -4 addr show "${INT}" | grep inet || true

echo "== 2/3 Ressourcen pruefen =="
MEM_MB=$(free -m | awk '/Mem:/{print $2}')
echo "Arbeitsspeicher in der VM: ${MEM_MB} MB"
if [ "${MEM_MB}" -lt 5500 ]; then
  echo "WARNUNG: Wazuh empfiehlt 8 GB RAM. Mit weniger kann die Installation scheitern oder langsam sein." >&2
fi

echo "== 3/3 Wazuh installieren (dauert ca. 10-20 Minuten) =="
cd "$HOME"
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
sudo bash ./wazuh-install.sh -a 2>&1 | tee wazuh-install.log

echo
echo "Fertig. Zugangsdaten stehen oben in der Zusammenfassung (Benutzer 'admin')."
echo "Nochmals anzeigen:"
echo "  sudo tar -O -xvf ~/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"
echo "Dashboard auf deinem PC: https://127.0.0.1:8443  (Zertifikatswarnung bestaetigen)"

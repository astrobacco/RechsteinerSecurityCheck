#!/usr/bin/env bash
# Rechsteiner Cyber Check - Demo-Labor: Scanner mit Greenbone Community Edition (laeuft IN der VM rcc-scanner)
# Aufruf in der VM:  bash 03-scanner-greenbone.sh
set -euo pipefail

echo "== 1/4 Feste IP im internen Netz (10.10.10.11) =="
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
      addresses: [10.10.10.11/24]
EOF
sudo chmod 600 /etc/netplan/60-buero.yaml
sudo netplan apply

echo "== 2/4 Docker installieren =="
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER" || true

echo "== 3/4 Greenbone Community Edition herunterladen und starten =="
DOWNLOAD_DIR="$HOME/greenbone-community-edition"
mkdir -p "$DOWNLOAD_DIR"
curl -f -O -L https://greenbone.github.io/docs/latest/_static/compose.yaml --output-dir "$DOWNLOAD_DIR"
sudo docker compose -f "$DOWNLOAD_DIR/compose.yaml" pull
sudo docker compose -f "$DOWNLOAD_DIR/compose.yaml" up -d

echo "== 4/4 Admin-Passwort setzen =="
echo "Standardmaessig ist das Passwort 'admin' (unsicher). Wahle jetzt ein eigenes."
read -r -s -p "Neues Passwort fuer 'admin': " PW
echo
for i in $(seq 1 60); do
  if sudo docker compose -f "$DOWNLOAD_DIR/compose.yaml" exec -u gvmd gvmd gvmd --user=admin --new-password="$PW" >/dev/null 2>&1; then
    echo "Passwort gesetzt."
    break
  fi
  echo "gvmd startet noch ... ($i/60)"
  sleep 20
done

echo
echo "Greenbone laedt jetzt seine Schwachstellen-Daten (Feed). Das dauert je nach Leitung 30-60 Minuten oder mehr."
echo "Fortschritt:  sudo docker compose -f $DOWNLOAD_DIR/compose.yaml logs -f"
echo
echo "Web-Oberflaeche auf deinem PC (in einer PowerShell, offen lassen):"
echo "  ssh -p 2222 -L 9443:127.0.0.1:443 $USER@127.0.0.1"
echo "Dann im Browser: https://127.0.0.1:9443  (Benutzer admin)"

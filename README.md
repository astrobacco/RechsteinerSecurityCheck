# Rechsteiner Cyber Check

Cybersecurity-Check für kleine Büros: ein Demo-Labor und Prüfskripte auf Basis von Wazuh (Endgeräte) und Greenbone/OpenVAS (Netzwerk). Gedacht für ein kleines Büro ohne IT-Abteilung, bei dem es einfach laufen soll.

Stand: November 2026. Privates Hobby- und Lernprojekt.

## Idee in einem Satz

Das Netz und die PCs eines kleinen Büros prüfen, die Funde in normalem Deutsch zusammenfassen und die Massnahmen priorisieren.

## Aktueller Stand

**Demo-Labor (VirtualBox, lokal, nur internes Netz `rcc-buero` 10.10.10.0/24):**

| VM | Zweck | Stand |
|---|---|---|
| `rcc-wazuh` | Wazuh 4.14.9 All-in-one auf Ubuntu 26.04, Dashboard über `https://127.0.0.1:8443` | läuft |
| `rcc-scanner` | Greenbone Community Edition per Docker auf Ubuntu 26.04, Zugriff per SSH-Tunnel | läuft, Feed-Sync zuletzt unklar, prüfen |
| `buero-pc1` | Windows 11 Enterprise Evaluation (90 Tage), Demo-Daten `C:\Firma`, Backup `C:\Backup` mit absichtlich leerem Ordner «Bestellungen», Wazuh-Agent | läuft, Agent im Dashboard sichtbar |
| `buero-nas` | Metasploitable 2, absichtlich verwundbar, nur internes Netz | noch nicht angelegt |

Abweichungen von der ursprünglichen `LAB-ANLEITUNG.md`: Ubuntu 26.04 statt 24.04, DHCP-Adressen statt fester 10.10.10.10/.11 (der Agent verbindet sich mit der aktuellen DHCP-Adresse von `rcc-wazuh`, die sich ändern kann), Windows-Setup über `lab-windows-setup.ps1`.

## Dateien

| Pfad | Inhalt |
|---|---|
| `lab/lab.ps1` | VMs anlegen, starten, stoppen, Snapshots (`check`, `vorbereiten`, `erstellen`, `start`, `stop`, `status`, `snapshot`, `zuruecksetzen`) |
| `lab/scripts/02-server-wazuh.sh` | Wazuh in der Server-VM installieren |
| `lab/scripts/03-scanner-greenbone.sh` | Greenbone per Docker in der Scanner-VM |
| `lab/share/windows-demo.ps1` | Demo-Daten anlegen (`setup`) und Backup-Wiederherstellungstest (`test`) |
| `lab/share/lab-windows-setup.ps1` | Demo-Daten, Wazuh-Server im Netz suchen, Agent installieren |
| `lab/share/rcc-pc-check.ps1` | Prüfskript für Büro-PCs (nur lesend): Updates, Defender, Firewall, BitLocker, RDP, SMB1, Konten, Freigaben, Ports, Backup. Erzeugt HTML-Report, CSV, JSON. **Noch nicht getestet.** |
| `lab/LAB-ANLEITUNG.md` | Schritt-für-Schritt-Anleitung für das Labor (teilweise veraltet, siehe oben) |

## Offene Punkte

- Snapshots der sauberen VMs (`.\lab.ps1 snapshot`) und Greenbone-Feed prüfen.
- `rcc-wazuh`: Dienst `wazuh-manager` ist beim ersten Boot einmal nicht gestartet und musste von Hand neu gestartet werden. Ursache klären (Startreihenfolge).
- Feste IP für `rcc-wazuh`, damit der Agent stabil verbindet.
- NAS-VM (Metasploitable) anlegen und einen Testscan auf `10.10.10.0/24` fahren.
- `rcc-pc-check.ps1` in `buero-pc1` testen und die Gewichtung des Scores anpassen.
- Berichtsvorlage, abgestimmt auf die Ausgabe des Prüfskripts.
- `LAB-ANLEITUNG.md` an den tatsächlichen Aufbau anpassen.

## Hinweise

Das Labor dient nur Tests und Vorführungen mit erfundenen Daten. Scans nie auf das Heim- oder Firmennetz. Metasploitable nie mit NAT oder Bridge betreiben.

Keine Passwörter, ISOs oder VM-Images in dieses Repository legen (siehe `.gitignore`).

# Demo-Labor für Rechsteiner Cyber Check (VirtualBox)

Ein Mini-Büro auf deinem PC, an dem du die Prüfungen testen und vorführen kannst. Alles läuft lokal, kein fremdes Netz wird angefasst.

```
 Dein PC (Host)
  |
  |  Internes Netz "rcc-buero"  10.10.10.0/24  (DHCP .100 bis .200)
  |
  +-- rcc-wazuh    10.10.10.10   "Server im Rechenzentrum": Wazuh -> https://127.0.0.1:8443
  +-- rcc-scanner  10.10.10.11   "Prüfgerät im Büro": Greenbone/OpenVAS
  +-- buero-pc1    DHCP          "Büro-PC": Windows mit Wazuh-Agent
  +-- buero-nas    DHCP          "NAS": Metasploitable 2, absichtlich löchrig, NUR internes Netz
```

Warum zwei Server-VMs? Greenbone und das Wazuh-Dashboard wollen beide Port 443. Und es entspricht deinem echten Aufbau: Wazuh zentral, der Scanner im Büronetz.

## Was dein PC mitbringen muss

| | knapp (unter 28 GB RAM) | normal (ab 28 GB RAM) |
|---|---|---|
| rcc-wazuh | 6 GB RAM, 4 CPU | 8 GB RAM, 4 CPU |
| rcc-scanner | 4 GB RAM, 2 CPU | 6 GB RAM, 2 CPU |
| buero-pc1 | 3 GB RAM, 2 CPU | 4 GB RAM, 2 CPU |
| buero-nas | 0,5 GB RAM | 0,5 GB RAM |
| Summe | ca. 14 GB | ca. 19 GB |

Plattenplatz: rechne mit 100 GB frei (die virtuellen Platten wachsen erst beim Benutzen). `lab.ps1` wählt das Profil automatisch. Bei 16 GB RAM startest du nicht alles gleichzeitig, siehe «Wenig RAM» unten.

## Schritt 0: Downloads (ca. 10 GB, mach das zuerst)

Lege die Dateien in diese Ordner (Ordner `iso` und `images` legt `lab.ps1` an, oder du erstellst sie selbst) und benenne sie genau so um:

| Was | Wo herunterladen | Speichern als |
|---|---|---|
| VirtualBox 7.x | virtualbox.org/wiki/Downloads | (installieren) |
| Ubuntu Server 24.04 LTS | ubuntu.com/download/server | `lab\iso\ubuntu.iso` |
| Windows 11 Enterprise Evaluation (90 Tage) | microsoft.com/evalcenter | `lab\iso\windows.iso` |
| Metasploitable 2 (ZIP entpacken, die `.vmdk` nehmen) | sourceforge.net/projects/metasploitable | `lab\images\Metasploitable.vmdk` |

Lädst du die Dateien einfach in den normalen Downloads-Ordner, erledigt `.\lab.ps1 vorbereiten` das Kopieren und Umbenennen (und entpackt das Metasploitable-ZIP). Es liegt danach alles doppelt auf der Platte, die Originale kannst du später löschen.

Windows 10 statt 11 geht auch: `.\lab.ps1 erstellen -Windows 10`.
Falls Metasploitable 2 nicht mehr verfügbar ist, nimm eine andere absichtlich verwundbare VM (z. B. von vulnhub.com). Die NAS-VM ist optional.

## Schritt 1: VMs anlegen (5 Minuten)

PowerShell öffnen, in den Ordner wechseln:

```powershell
cd D:\rechsteiner-cybercheck\lab
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\lab.ps1 check
.\lab.ps1 erstellen
```

Das `Set-ExecutionPolicy` gilt nur für dieses PowerShell-Fenster. Öffnest du später ein neues, führst du es vorher nochmal aus, sonst blockiert Windows die Skripte.

`check` zeigt RAM, Platz und ob Hyper-V/WSL2/Docker Desktop VirtualBox ausbremst. `erstellen` legt das interne Netz und alle VMs an, die ISOs sind schon eingelegt. Die VMs liegen in `lab\vms`.

## Schritt 2: Ubuntu auf beiden Servern installieren (je ca. 15 Minuten)

Starte `rcc-wazuh` im VirtualBox Manager (Doppelklick, nicht per Skript, du brauchst das Fenster für den Installer).

- Sprache English, Tastatur Swiss German.
- Netzwerk: nichts ändern (beide Karten per DHCP).
- Speicher: «Use an entire disk», den Haken bei **LVM abwählen**. Sonst nutzt Ubuntu nur die Hälfte der Platte.
- Servername `rcc-wazuh`, Benutzer `rcc`, ein Passwort, das du dir merkst.
- **Install OpenSSH server: ja.** Keine Zusatzpakete (Snaps) auswählen.
- Am Ende «Reboot Now». Wenn er nach dem Entfernen des Installationsmediums fragt, Enter drücken.

Dann dasselbe für `rcc-scanner` (Servername `rcc-scanner`, ebenfalls Benutzer `rcc`).

Danach laufen beide ohne Fenster: `.\lab.ps1 start -Nur rcc-wazuh,rcc-scanner`.

## Schritt 3: Wazuh und Greenbone einrichten

Die Skripte laufen in den VMs. Du kopierst sie per SSH hinein (OpenSSH-Client ist in Windows 10/11 schon drin).

**Wazuh** (Port 2223):

```powershell
scp -P 2223 scripts\02-server-wazuh.sh rcc@127.0.0.1:~
ssh -p 2223 rcc@127.0.0.1
bash 02-server-wazuh.sh
```

Dauert 10 bis 20 Minuten. Am Schluss zeigt es den Benutzer `admin` und das Passwort. Notiere es. Dashboard: `https://127.0.0.1:8443` (Zertifikatswarnung bestätigen).

**Greenbone** (Port 2222), in einer zweiten PowerShell:

```powershell
scp -P 2222 scripts\03-scanner-greenbone.sh rcc@127.0.0.1:~
ssh -p 2222 rcc@127.0.0.1
bash 03-scanner-greenbone.sh
```

Das Skript fragt nach einem neuen Admin-Passwort. Danach lädt Greenbone seine Schwachstellen-Daten, das dauert **30 bis 60 Minuten oder länger**. Erst danach liefern Scans brauchbare Ergebnisse. Die Oberfläche hört nur auf `127.0.0.1` in der VM, deshalb per SSH-Tunnel (Fenster offen lassen):

```powershell
ssh -p 2222 -L 9443:127.0.0.1:443 rcc@127.0.0.1
```

Im Browser: `https://127.0.0.1:9443`, Benutzer `admin`.

## Schritt 4: Windows-PC einrichten

`buero-pc1` im VirtualBox Manager starten.

- Meldet Windows 11 «Dieser PC kann Windows 11 nicht ausführen»: Shift+F10, dann diese drei Zeilen, Fenster schliessen, Installation fortsetzen:
  ```
  reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1
  reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1
  reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1
  ```
- Verlangt Windows ein Microsoft-Konto: Shift+F10, `oobe\bypassnro`, es startet neu und bietet «Ich habe kein Internet» an. Dann lokales Konto.
- Menü **Geräte → Gastzusätze-CD-Image einlegen**, im Explorer das CD-Laufwerk öffnen, installieren, neu starten.
- Im Explorer `\\VBoxSvr\rcc-lab` öffnen und `windows-demo.ps1` auf den Desktop kopieren.
- In PowerShell auf dem Desktop:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\windows-demo.ps1 setup
  ```
  Das legt Demo-Firmendaten in `C:\Firma` an und ein Backup in `C:\Backup`, bei dem der Ordner «Bestellungen» **absichtlich leer** ist (genau wie im Beispielbericht).

**Wazuh-Agent installieren:** Im Wazuh-Dashboard bei den Agents «Deploy new agent» wählen, Windows, als Server-Adresse `10.10.10.10`, als Name `buero-pc1`. Den angezeigten Befehl kopierst du in eine Administrator-PowerShell im Windows-PC und startest danach den Dienst (`NET START Wazuh`). Nach einer Minute erscheint der PC im Dashboard.

## Schritt 5: NAS starten

`.\lab.ps1 start -Nur buero-nas`. Metasploitable 2 hat bekannte Zugangsdaten (`msfadmin`/`msfadmin`) und absichtlich offene, veraltete Dienste. Genau deshalb hängt sie nur am internen Netz, hat keinen Weg ins Internet und darf **nie** mit NAT oder Bridge-Adapter laufen.

## Schritt 6: Sauberen Zustand sichern

Wenn alles läuft (Agent im Dashboard grün, Greenbone-Feed geladen):

```powershell
.\lab.ps1 stop
.\lab.ps1 snapshot
```

Vor jeder Vorführung: `.\lab.ps1 zuruecksetzen`, dann `.\lab.ps1 start`.

## Die Vorführung (ca. 10 Minuten)

Starte die VMs 5 Minuten vorher. Sag am Anfang klar, dass es ein Testbüro mit erfundenen Daten ist.

1. **Der Computer (Wazuh):** Agent `buero-pc1` ist verbunden. Zeig den Bereich «Configuration Assessment» (Prüfergebnis gegen einen Sicherheitsstandard, mit Punktzahl) und die erkannten Schwachstellen. «So sehe ich jeden Computer, ohne dass jemand etwas tun muss.»
2. **Das Netzwerk (Greenbone):** Lege vorher einen Scan auf `10.10.10.0/24` an (Scan-Konfiguration «Full and fast») und zeig das fertige Ergebnis. Beim NAS gibt es viele rote Funde. Das sind die Funde, die später in den Bericht kommen. Für den Windows-PC setzt du beim Ziel «Alive Test» auf «Consider Alive», sonst hält Greenbone ihn wegen der Windows-Firewall für abwesend.
3. **Das Backup:** Im Windows-PC `powershell -ExecutionPolicy Bypass -File .\windows-demo.ps1 test`. Die Tabelle zeigt «Bestellungen: FEHLER». «Das Backup läuft, aber es sichert nichts mehr. Das merkt kaum jemand.»

## Eigene Tests

Das Labor ist deine Testumgebung: Neue Prüfungen (z. B. offene Ports, fehlende Updates) hier ausprobieren. Scans nur auf `10.10.10.0/24`, **nie** auf dein Heim- oder Firmennetz.

## Wenn etwas nicht klappt

- **Wenig RAM (16 GB):** Starte nur, was du brauchst. Für den Windows-PC mit Wazuh: `.\lab.ps1 start -Nur rcc-wazuh,buero-pc1`. Den Scanner (und das NAS) nur zum Scannen dazunehmen.
- **Alles langsam:** Ist Hyper-V, WSL2 oder Docker Desktop aktiv, läuft VirtualBox deutlich langsamer. `lab.ps1 check` zeigt das an.
- **Agent verbindet nicht:** Im Windows-PC `ping 10.10.10.10` prüfen. Geht das nicht, in den VM-Einstellungen kontrollieren, dass Adapter 2 «Internes Netzwerk» mit dem Namen `rcc-buero` ist.
- **Zweite Netzwerkkarte nicht gefunden (Skriptfehler):** Dasselbe prüfen, VM ausschalten, Adapter 2 korrigieren.
- **Windows läuft ab:** Die Evaluationsversion gilt 90 Tage. Danach baust du die VM neu aus der ISO. Ein Snapshot verlängert die Frist nicht.
- **Alles neu:** `.\lab.ps1 stop`, dann die VMs im VirtualBox Manager löschen (Alle Dateien entfernen) und `erstellen` nochmal ausführen.

## Hinweise

Die Skripte folgen den offiziellen Anleitungen von VirtualBox, Wazuh (Version 4.14) und Greenbone, sind aber noch nicht auf deinem PC gelaufen. Wenn eine Zeile einen Fehler wirft, kopiere die Meldung in den Chat.

# Rechsteiner Cyber Check - PC-Check fuer Buero-PCs (nur lesend, aendert nichts am System)
#
# Start (am besten als Administrator, sonst koennen BitLocker/SMB1/Secure Boot nicht geprueft werden):
#   powershell -ExecutionPolicy Bypass -File .\rcc-pc-check.ps1
# Optional mit Backup-Wiederherstellungstest (vergleicht Dateien aus der Quelle mit dem Backup):
#   powershell -ExecutionPolicy Bypass -File .\rcc-pc-check.ps1 -QuellePfad C:\Firma -BackupPfad C:\Backup
# Ergebnis: Ordner "rcc-check-<PC-Name>" auf dem Desktop mit report.html, ergebnisse.csv,
#           ergebnisse.json und programme.csv.
# Nur ASCII-Zeichen, damit Windows PowerShell 5.1 die Datei fehlerfrei liest.

param(
    [string]$Ausgabe = '',
    [string]$QuellePfad = '',
    [string]$BackupPfad = ''
)

$ErrorActionPreference = 'Continue'
if (-not $Ausgabe) {
    $Ausgabe = Join-Path ([Environment]::GetFolderPath('Desktop')) ('rcc-check-' + $env:COMPUTERNAME)
}
New-Item -ItemType Directory -Force $Ausgabe | Out-Null

$istAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:Liste = New-Object System.Collections.ArrayList

function Add-Pruefung {
    param([string]$Bereich, [string]$Pruefung, [string]$Status, [string]$Detail, [int]$Gewicht = 0)
    [void]$script:Liste.Add([pscustomobject]@{
            Bereich  = $Bereich
            Pruefung = $Pruefung
            Status   = $Status
            Detail   = $Detail
            Gewicht  = $Gewicht
        })
}

function Add-NichtPruefbar {
    param([string]$Bereich, [string]$Pruefung, [string]$Grund)
    Add-Pruefung $Bereich $Pruefung 'INFO' ("Nicht pruefbar: " + $Grund) 0
}

Write-Host "Rechsteiner Cyber Check - PC-Check auf $env:COMPUTERNAME" -ForegroundColor Cyan
if (-not $istAdmin) {
    Write-Host 'Hinweis: Kein Administrator. Einige Pruefungen (BitLocker, SMB1, Secure Boot) sind eingeschraenkt.' -ForegroundColor Yellow
}

# --- System und Support ---
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $name = $os.Caption
    if ($name -match 'Windows (7|8|Vista|XP)' -or $name -match 'Server 2008|Server 2012') {
        Add-Pruefung 'System' 'Windows-Version' 'FEHLER' "$name (Build $build): Herstellersupport beendet" 3
    }
    elseif ($name -match 'Windows 10') {
        Add-Pruefung 'System' 'Windows-Version' 'FEHLER' "$name (Build $build): Support ist am 14.10.2025 ausgelaufen, nur mit bezahltem ESU weiter Updates" 3
    }
    elseif ($name -match 'Windows 11' -and $build -lt 26100) {
        Add-Pruefung 'System' 'Windows-Version' 'WARNUNG' "$name (Build $build): aeltere Windows-11-Version, Funktionsupdate auf 24H2 oder neuer pruefen" 3
    }
    else {
        Add-Pruefung 'System' 'Windows-Version' 'OK' "$name (Build $build)" 3
    }
    $boot = $os.LastBootUpTime
    $tageLaufzeit = [int]((Get-Date) - $boot).TotalDays
    if ($tageLaufzeit -gt 30) {
        Add-Pruefung 'System' 'Letzter Neustart' 'WARNUNG' "Vor $tageLaufzeit Tagen. Updates werden oft erst nach einem Neustart aktiv" 1
    }
    else {
        Add-Pruefung 'System' 'Letzter Neustart' 'OK' "Vor $tageLaufzeit Tagen" 1
    }
}
catch { Add-NichtPruefbar 'System' 'Windows-Version' $_.Exception.Message }

# --- Updates ---
try {
    $hf = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($hf) {
        $tage = [int]((Get-Date) - $hf.InstalledOn).TotalDays
        $text = "Letztes Update " + $hf.HotFixID + " vor $tage Tagen"
        if ($tage -le 45) { Add-Pruefung 'Updates' 'Letzte installierte Updates' 'OK' $text 3 }
        elseif ($tage -le 90) { Add-Pruefung 'Updates' 'Letzte installierte Updates' 'WARNUNG' $text 3 }
        else { Add-Pruefung 'Updates' 'Letzte installierte Updates' 'FEHLER' $text 3 }
    }
    else {
        Add-Pruefung 'Updates' 'Letzte installierte Updates' 'WARNUNG' 'Keine Update-Eintraege gefunden' 3
    }
    $ausstehend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    if ($ausstehend) { Add-Pruefung 'Updates' 'Neustart ausstehend' 'WARNUNG' 'Ein Neustart wegen Updates steht aus' 1 }
    else { Add-Pruefung 'Updates' 'Neustart ausstehend' 'OK' 'Kein Neustart ausstehend' 1 }
}
catch { Add-NichtPruefbar 'Updates' 'Updates' $_.Exception.Message }

# --- Virenschutz ---
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.RealTimeProtectionEnabled) { Add-Pruefung 'Virenschutz' 'Defender Echtzeitschutz' 'OK' 'Aktiv' 3 }
    else { Add-Pruefung 'Virenschutz' 'Defender Echtzeitschutz' 'FEHLER' 'Ausgeschaltet' 3 }
    $alter = [int]$mp.AntivirusSignatureAge
    $t = "Signaturen $alter Tage alt"
    if ($alter -le 3) { Add-Pruefung 'Virenschutz' 'Defender Signaturen' 'OK' $t 2 }
    elseif ($alter -le 7) { Add-Pruefung 'Virenschutz' 'Defender Signaturen' 'WARNUNG' $t 2 }
    else { Add-Pruefung 'Virenschutz' 'Defender Signaturen' 'FEHLER' $t 2 }
}
catch {
    try {
        $av = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
        $namen = ($av | ForEach-Object { $_.displayName }) -join ', '
        Add-Pruefung 'Virenschutz' 'Virenschutz-Produkt' 'INFO' "Drittanbieter registriert: $namen. Aktualitaet manuell pruefen" 0
    }
    catch { Add-Pruefung 'Virenschutz' 'Virenschutz-Produkt' 'WARNUNG' 'Kein Virenschutz erkannt' 3 }
}

# --- Firewall ---
try {
    $aus = @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
    if ($aus.Count -eq 0) { Add-Pruefung 'Netzwerk' 'Windows-Firewall' 'OK' 'Alle Profile aktiv' 3 }
    else { Add-Pruefung 'Netzwerk' 'Windows-Firewall' 'FEHLER' ('Ausgeschaltet bei: ' + ($aus -join ', ')) 3 }
}
catch { Add-NichtPruefbar 'Netzwerk' 'Windows-Firewall' $_.Exception.Message }

# --- Verschluesselung ---
if ($istAdmin) {
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ("$($bl.ProtectionStatus)" -eq 'On') { Add-Pruefung 'Daten' 'BitLocker Systemlaufwerk' 'OK' 'Aktiv' 3 }
        else { Add-Pruefung 'Daten' 'BitLocker Systemlaufwerk' 'FEHLER' 'Nicht aktiv. Bei Diebstahl (v.a. Laptops) sind alle Daten lesbar' 3 }
    }
    catch { Add-NichtPruefbar 'Daten' 'BitLocker Systemlaufwerk' 'BitLocker nicht verfuegbar (z.B. Windows Home)' }
}
else { Add-NichtPruefbar 'Daten' 'BitLocker Systemlaufwerk' 'Administrator-Rechte noetig' }

try {
    $tpm = Get-Tpm -ErrorAction Stop
    if ($tpm.TpmPresent) { Add-Pruefung 'Daten' 'TPM' 'OK' 'Vorhanden' 0 }
    else { Add-Pruefung 'Daten' 'TPM' 'INFO' 'Kein TPM gefunden' 0 }
}
catch { Add-NichtPruefbar 'Daten' 'TPM' $_.Exception.Message }

if ($istAdmin) {
    try {
        if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Pruefung 'System' 'Secure Boot' 'OK' 'Aktiv' 1 }
        else { Add-Pruefung 'System' 'Secure Boot' 'WARNUNG' 'Ausgeschaltet' 1 }
    }
    catch { Add-NichtPruefbar 'System' 'Secure Boot' 'Nicht unterstuetzt (Legacy-BIOS) oder nicht lesbar' }
}

# --- Fernzugriff und alte Protokolle ---
try {
    $deny = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop).fDenyTSConnections
    if ($deny -eq 1) { Add-Pruefung 'Netzwerk' 'Remotedesktop (RDP)' 'OK' 'Ausgeschaltet' 2 }
    else {
        $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue).UserAuthentication
        if ($nla -eq 1) { Add-Pruefung 'Netzwerk' 'Remotedesktop (RDP)' 'WARNUNG' 'Eingeschaltet (mit NLA). Nur wenn noetig, nie direkt aus dem Internet erreichbar' 2 }
        else { Add-Pruefung 'Netzwerk' 'Remotedesktop (RDP)' 'FEHLER' 'Eingeschaltet ohne Netzwerkauthentifizierung (NLA)' 2 }
    }
}
catch { Add-NichtPruefbar 'Netzwerk' 'Remotedesktop (RDP)' $_.Exception.Message }

if ($istAdmin) {
    try {
        $smb1 = (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
        if ($smb1) { Add-Pruefung 'Netzwerk' 'SMB1 (veraltet)' 'FEHLER' 'SMB1 ist aktiv, Einfallstor fuer Ransomware (z.B. WannaCry)' 2 }
        else { Add-Pruefung 'Netzwerk' 'SMB1 (veraltet)' 'OK' 'Ausgeschaltet' 2 }
    }
    catch { Add-NichtPruefbar 'Netzwerk' 'SMB1 (veraltet)' $_.Exception.Message }
}
else { Add-NichtPruefbar 'Netzwerk' 'SMB1 (veraltet)' 'Administrator-Rechte noetig' }

try {
    $ports = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' } |
            ForEach-Object { [int]$_.LocalPort } | Sort-Object -Unique)
    $riskant = @($ports | Where-Object { $_ -in 21, 23, 5900 })
    $text = 'Offene Ports: ' + ($ports -join ', ')
    if ($riskant.Count -gt 0) {
        Add-Pruefung 'Netzwerk' 'Lauschende Ports' 'WARNUNG' ($text + '. Unsicher: ' + ($riskant -join ', ') + ' (FTP/Telnet/VNC)') 2
    }
    else { Add-Pruefung 'Netzwerk' 'Lauschende Ports' 'OK' $text 2 }
}
catch { Add-NichtPruefbar 'Netzwerk' 'Lauschende Ports' $_.Exception.Message }

# --- Konten und Anmeldung ---
try {
    $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    $namen = ($admins | ForEach-Object { $_.Name }) -join ', '
    if ($admins.Count -le 2) { Add-Pruefung 'Konten' 'Administrator-Konten' 'OK' ("$($admins.Count) Konten: $namen") 2 }
    else { Add-Pruefung 'Konten' 'Administrator-Konten' 'WARNUNG' ("$($admins.Count) Konten mit Admin-Rechten: $namen. Weniger ist besser") 2 }
}
catch { Add-NichtPruefbar 'Konten' 'Administrator-Konten' $_.Exception.Message }

try {
    $lokale = @(Get-LocalUser -ErrorAction Stop)
    $gast = @($lokale | Where-Object { $_.Enabled -and $_.SID.Value -like '*-501' })
    if ($gast.Count -gt 0) { Add-Pruefung 'Konten' 'Gastkonto' 'FEHLER' 'Gastkonto ist aktiv' 1 }
    else { Add-Pruefung 'Konten' 'Gastkonto' 'OK' 'Deaktiviert' 1 }
    $ohnePw = @($lokale | Where-Object { $_.Enabled -and -not $_.PasswordRequired } | ForEach-Object { $_.Name })
    if ($ohnePw.Count -gt 0) { Add-Pruefung 'Konten' 'Konten ohne Passwortpflicht' 'FEHLER' ('Aktiv ohne Passwort: ' + ($ohnePw -join ', ')) 3 }
    else { Add-Pruefung 'Konten' 'Konten ohne Passwortpflicht' 'OK' 'Alle aktiven lokalen Konten brauchen ein Passwort' 3 }
}
catch { Add-NichtPruefbar 'Konten' 'Lokale Konten' $_.Exception.Message }

try {
    $lua = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop).EnableLUA
    if ($lua -eq 1) { Add-Pruefung 'Konten' 'Benutzerkontensteuerung (UAC)' 'OK' 'Aktiv' 2 }
    else { Add-Pruefung 'Konten' 'Benutzerkontensteuerung (UAC)' 'FEHLER' 'Ausgeschaltet' 2 }
}
catch { Add-NichtPruefbar 'Konten' 'Benutzerkontensteuerung (UAC)' $_.Exception.Message }

try {
    $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
    $pwGespeichert = $null -ne $wl.DefaultPassword
    if ($pwGespeichert) { Add-Pruefung 'Konten' 'Automatische Anmeldung' 'FEHLER' 'Passwort im Klartext in der Registry gespeichert' 3 }
    elseif ($wl.AutoAdminLogon -eq '1') { Add-Pruefung 'Konten' 'Automatische Anmeldung' 'WARNUNG' 'Automatische Anmeldung ist aktiv' 2 }
    else { Add-Pruefung 'Konten' 'Automatische Anmeldung' 'OK' 'Nicht aktiv' 2 }
}
catch { Add-NichtPruefbar 'Konten' 'Automatische Anmeldung' $_.Exception.Message }

# --- Freigaben ---
try {
    $freigaben = @(Get-SmbShare -ErrorAction Stop | Where-Object { -not $_.Special })
    if ($freigaben.Count -eq 0) { Add-Pruefung 'Daten' 'Netzwerkfreigaben' 'OK' 'Keine eigenen Freigaben' 2 }
    else {
        $offen = @()
        foreach ($f in $freigaben) {
            $zugriff = @(Get-SmbShareAccess -Name $f.Name -ErrorAction SilentlyContinue)
            foreach ($z in $zugriff) {
                $jeder = ($z.AccountName -match 'Everyone|Jeder|Tout le monde|Tutti') -and ("$($z.AccessControlType)" -eq 'Allow')
                if ($jeder -and ("$($z.AccessRight)" -in 'Full', 'Change')) { $offen += ($f.Name + ' (' + $z.AccessRight + ')') }
            }
        }
        $liste = ($freigaben | ForEach-Object { $_.Name + ' -> ' + $_.Path }) -join '; '
        if ($offen.Count -gt 0) { Add-Pruefung 'Daten' 'Netzwerkfreigaben' 'FEHLER' ('Fuer Jeden beschreibbar: ' + ($offen -join ', ') + '. Alle: ' + $liste) 2 }
        else { Add-Pruefung 'Daten' 'Netzwerkfreigaben' 'INFO' ('Eigene Freigaben (Berechtigungen pruefen): ' + $liste) 0 }
    }
}
catch { Add-NichtPruefbar 'Daten' 'Netzwerkfreigaben' $_.Exception.Message }

# --- Backup ---
try {
    $schatten = @(Get-CimInstance Win32_ShadowCopy -ErrorAction Stop).Count
    Add-Pruefung 'Backup' 'Schattenkopien' 'INFO' "$schatten Schattenkopien vorhanden. Ein Backup ist erst bewiesen, wenn eine Wiederherstellung klappt" 0
}
catch { Add-NichtPruefbar 'Backup' 'Schattenkopien' $_.Exception.Message }

if ($QuellePfad -and $BackupPfad) {
    try {
        if (-not (Test-Path $QuellePfad)) { throw "Quelle nicht gefunden: $QuellePfad" }
        if (-not (Test-Path $BackupPfad)) { throw "Backup nicht gefunden: $BackupPfad" }
        $quelle = (Resolve-Path $QuellePfad).Path.TrimEnd('\')
        $dateien = @(Get-ChildItem $quelle -File -Recurse -ErrorAction SilentlyContinue)
        if ($dateien.Count -eq 0) { throw "Keine Dateien in der Quelle gefunden: $QuellePfad" }
        $probe = @($dateien | Get-Random -Count ([math]::Min(100, $dateien.Count)))
        $ok = 0; $fehlt = 0; $abweichend = 0
        foreach ($f in $probe) {
            $rel = $f.FullName.Substring($quelle.Length).TrimStart('\')
            $kopie = Join-Path $BackupPfad $rel
            if (-not (Test-Path $kopie)) { $fehlt++ }
            elseif ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $kopie).Hash) { $abweichend++ }
            else { $ok++ }
        }
        $text = "Stichprobe $($probe.Count) von $($dateien.Count) Dateien: $ok wiederherstellbar, $fehlt fehlen im Backup, $abweichend weichen ab"
        if ($probe.Count -gt 0 -and $ok -eq $probe.Count) { Add-Pruefung 'Backup' 'Wiederherstellungstest' 'OK' $text 3 }
        else { Add-Pruefung 'Backup' 'Wiederherstellungstest' 'FEHLER' $text 3 }
    }
    catch { Add-NichtPruefbar 'Backup' 'Wiederherstellungstest' $_.Exception.Message }
}
else {
    Add-Pruefung 'Backup' 'Wiederherstellungstest' 'INFO' 'Nicht ausgefuehrt. Mit -QuellePfad und -BackupPfad starten' 0
}

# --- Installierte Programme (fuer spaetere Schwachstellen-Abgleiche) ---
try {
    $schluessel = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $programme = Get-ItemProperty $schluessel -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName -Unique
    $programme | Export-Csv -Path (Join-Path $Ausgabe 'programme.csv') -NoTypeInformation -Encoding UTF8
    Add-Pruefung 'Software' 'Installierte Programme' 'INFO' ("$(@($programme).Count) Programme, Liste in programme.csv") 0
}
catch { Add-NichtPruefbar 'Software' 'Installierte Programme' $_.Exception.Message }

# --- Bewertung ---
$bewertet = @($script:Liste | Where-Object { $_.Gewicht -gt 0 })
$max = 0; $ist = 0.0
foreach ($b in $bewertet) {
    $max += $b.Gewicht
    if ($b.Status -eq 'OK') { $ist += $b.Gewicht }
    elseif ($b.Status -eq 'WARNUNG') { $ist += ($b.Gewicht / 2) }
}
if ($max -gt 0) { $score = [int][math]::Round(100 * $ist / $max) } else { $score = 0 }
$anzFehler = @($script:Liste | Where-Object { $_.Status -eq 'FEHLER' }).Count
$anzWarn = @($script:Liste | Where-Object { $_.Status -eq 'WARNUNG' }).Count

# --- Ausgabe ---
$script:Liste | Export-Csv -Path (Join-Path $Ausgabe 'ergebnisse.csv') -NoTypeInformation -Encoding UTF8
$script:Liste | ConvertTo-Json | Set-Content -Path (Join-Path $Ausgabe 'ergebnisse.json') -Encoding UTF8

$farben = @{ OK = '#1a7f37'; WARNUNG = '#b8860b'; FEHLER = '#c62828'; INFO = '#555555' }
$zeilen = foreach ($e in $script:Liste) {
    $f = $farben[$e.Status]
    $d = [System.Net.WebUtility]::HtmlEncode($e.Detail)
    $p = [System.Net.WebUtility]::HtmlEncode($e.Pruefung)
    $b = [System.Net.WebUtility]::HtmlEncode($e.Bereich)
    "<tr><td>$b</td><td>$p</td><td style='color:$f;font-weight:bold'>$($e.Status)</td><td>$d</td></tr>"
}
$html = @"
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><title>Cyber Check - $($env:COMPUTERNAME)</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:2em;color:#222}table{border-collapse:collapse;width:100%}
td,th{border-bottom:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}th{background:#f4f4f4}
.score{font-size:2.5em;font-weight:bold}</style></head><body>
<h1>Cyber Check - PC-Pruefung</h1>
<p>Rechner: <b>$($env:COMPUTERNAME)</b> | Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm') | Administrator-Rechte: $istAdmin</p>
<p class="score">$score / 100</p>
<p>$anzFehler Fehler, $anzWarn Warnungen. Die Punktzahl ist eine Orientierung und gewichtet die Pruefungen nach Risiko.</p>
<table><tr><th>Bereich</th><th>Pruefung</th><th>Status</th><th>Details</th></tr>
$($zeilen -join "`n")
</table></body></html>
"@
Set-Content -Path (Join-Path $Ausgabe 'report.html') -Value $html -Encoding UTF8

Write-Host ''
$script:Liste | Format-Table Bereich, Pruefung, Status, Detail -AutoSize -Wrap
Write-Host "PUNKTZAHL: $score / 100   ($anzFehler Fehler, $anzWarn Warnungen)" -ForegroundColor Cyan
Write-Host "Ergebnisse gespeichert in: $Ausgabe" -ForegroundColor Green

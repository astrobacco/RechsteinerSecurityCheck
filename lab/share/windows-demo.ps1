# Rechsteiner Cyber Check - Demo-Daten und Backup-Test (laeuft IM Windows-PC buero-pc1)
# Aufruf in PowerShell:
#   .\windows-demo.ps1 setup    Demo-Firmendaten und ein absichtlich unvollstaendiges Backup anlegen
#   .\windows-demo.ps1 test     Backup-Test: Wiederherstellung in Testordner, Vergleich, Aufraeumen
# Nur ASCII-Zeichen, damit Windows PowerShell 5.1 die Datei fehlerfrei liest.

param(
    [Parameter(Position = 0)]
    [ValidateSet('setup', 'test')]
    [string]$Aktion = 'test'
)

$ErrorActionPreference = 'Stop'
$Quelle = 'C:\Firma'
$Backup = 'C:\Backup'

if ($Aktion -eq 'setup') {
    foreach ($ordner in 'Buchhaltung', 'Bestellungen', 'Kunden') {
        New-Item -ItemType Directory -Force "$Quelle\$ordner" | Out-Null
        1..8 | ForEach-Object {
            Set-Content -Path "$Quelle\$ordner\datei$_.txt" -Value "Beispieldaten $ordner Nr. $_ ($(Get-Random))"
        }
    }
    New-Item -ItemType Directory -Force "$Backup\Buchhaltung", "$Backup\Kunden", "$Backup\Bestellungen" | Out-Null
    Copy-Item "$Quelle\Buchhaltung\*" "$Backup\Buchhaltung" -Force
    Copy-Item "$Quelle\Kunden\*" "$Backup\Kunden" -Force
    # Der Ordner Bestellungen im Backup bleibt absichtlich LEER:
    # So sieht ein Backup aus, das "laeuft", aber nichts mehr sichert.
    Write-Host "Demo-Daten unter $Quelle, Backup unter $Backup angelegt (Bestellungen: leer)."
    return
}

# --- Backup-Test ---
$Test = Join-Path $env:TEMP 'rcc-restore-test'
if (Test-Path $Test) { Remove-Item $Test -Recurse -Force }
New-Item -ItemType Directory -Force $Test | Out-Null

$ergebnis = foreach ($ordner in Get-ChildItem $Quelle -Directory) {
    $name = $ordner.Name
    $backupOrdner = Join-Path $Backup $name
    $zielOrdner = Join-Path $Test $name
    New-Item -ItemType Directory -Force $zielOrdner | Out-Null
    # Wiederherstellung in den Testordner (bestehende Daten werden nicht angefasst)
    if (Test-Path $backupOrdner) {
        Copy-Item (Join-Path $backupOrdner '*') $zielOrdner -Recurse -Force -ErrorAction SilentlyContinue
    }
    $dateien = Get-ChildItem $ordner.FullName -File -Recurse
    $ok = 0; $fehlt = 0; $abweichend = 0
    foreach ($f in $dateien) {
        $rel = $f.FullName.Substring($ordner.FullName.Length).TrimStart('\')
        $kopie = Join-Path $zielOrdner $rel
        if (-not (Test-Path $kopie)) { $fehlt++ }
        elseif ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $kopie).Hash) { $abweichend++ }
        else { $ok++ }
    }
    if (($dateien.Count -gt 0) -and ($ok -eq $dateien.Count)) { $status = 'OK' } else { $status = 'FEHLER' }
    [pscustomobject]@{
        Ordner            = $name
        Dateien           = $dateien.Count
        Wiederherstellbar = $ok
        Fehlt             = $fehlt
        Abweichend        = $abweichend
        Status            = $status
    }
}

$ergebnis | Format-Table -AutoSize
Remove-Item $Test -Recurse -Force
if ($ergebnis | Where-Object { $_.Status -ne 'OK' }) {
    Write-Host "ERGEBNIS: Backup NICHT vollstaendig wiederherstellbar." -ForegroundColor Red
} else {
    Write-Host "ERGEBNIS: Alle Ordner vollstaendig wiederherstellbar." -ForegroundColor Green
}

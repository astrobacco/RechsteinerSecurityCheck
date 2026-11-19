# Rechsteiner Cyber Check - Windows-Setup fuer buero-pc1 (Demo-Daten + Wazuh-Agent)
# Start: Rechtsklick auf die Datei -> "Mit PowerShell ausfuehren" (Run with PowerShell).
# Das Skript fragt selbst nach Administrator-Rechten (UAC mit Ja bestaetigen).
# Nur ASCII-Zeichen, damit Windows PowerShell 5.1 die Datei fehlerfrei liest.

param([string]$Manager = '')

$ErrorActionPreference = 'Stop'
$work = Join-Path $env:TEMP 'rcc'

$istAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $istAdmin) {
    # Skripte nach C:\Users\...\Temp kopieren, weil das erhoehte Fenster das Laufwerk Z: nicht sieht
    New-Item -ItemType Directory -Force $work | Out-Null
    Copy-Item $PSCommandPath (Join-Path $work 'lab-windows-setup.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'windows-demo.ps1') $work -Force
    $argumente = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $work 'lab-windows-setup.ps1'))
    if ($Manager) { $argumente += @('-Manager', $Manager) }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argumente
    return
}

$log = 'C:\rcc-setup.log'
Start-Transcript -Path $log -Force | Out-Null
try {
    Write-Host '== 1/3 Demo-Daten anlegen ==' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'windows-demo.ps1') setup

    Write-Host '== 2/3 Wazuh-Server im internen Netz suchen (Port 1515) ==' -ForegroundColor Cyan
    if (-not $Manager) {
        $versuche = 1..254 | ForEach-Object {
            $c = New-Object System.Net.Sockets.TcpClient
            [pscustomobject]@{ Ip = "10.10.10.$_"; Client = $c; Task = $c.ConnectAsync("10.10.10.$_", 1515) }
        }
        Start-Sleep -Seconds 5
        $gefunden = @($versuche | Where-Object { $_.Task.Status -eq 'RanToCompletion' -and $_.Client.Connected } | ForEach-Object { $_.Ip })
        foreach ($v in $versuche) { try { $v.Client.Close() } catch { } }
        if ($gefunden.Count -eq 0) { throw 'Kein Wazuh-Server auf 10.10.10.x gefunden. Ist rcc-wazuh gestartet?' }
        $Manager = $gefunden[0]
    }
    Write-Host "Wazuh-Server: $Manager"

    Write-Host '== 3/3 Wazuh-Agent installieren ==' -ForegroundColor Cyan
    $msi = Join-Path $env:TEMP 'wazuh-agent.msi'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.9-1.msi' -OutFile $msi -UseBasicParsing
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /q WAZUH_MANAGER=`"$Manager`" WAZUH_AGENT_NAME=`"buero-pc1`"" -Wait -PassThru
    Write-Host "msiexec Exitcode: $($p.ExitCode)"
    Start-Service -Name 'WazuhSvc'
    Start-Sleep -Seconds 5
    Get-Service -Name 'WazuhSvc' | Format-Table Name, Status -AutoSize
    Write-Host 'FERTIG: Demo-Daten angelegt, Wazuh-Agent installiert und gestartet.' -ForegroundColor Green
}
catch {
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
}
Stop-Transcript | Out-Null
Read-Host 'Enter druecken zum Schliessen'

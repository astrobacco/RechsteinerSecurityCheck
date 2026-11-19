# Rechsteiner Cyber Check - Demo-Labor mit VirtualBox
# Aufruf in PowerShell (im Ordner lab):
#   .\lab.ps1 check            Rechner pruefen (RAM, Platz, VirtualBox-Version)
#   .\lab.ps1 vorbereiten      Downloads-Ordner nach ISOs/Metasploitable durchsuchen und kopieren
#   .\lab.ps1 erstellen        Alle 4 VMs und das interne Netz anlegen
#   .\lab.ps1 start            VMs starten      (optional: -Nur rcc-wazuh,buero-pc1)
#   .\lab.ps1 stop             VMs herunterfahren
#   .\lab.ps1 status           Zustand anzeigen
#   .\lab.ps1 snapshot         Snapshot "sauber" aller VMs erstellen (-Snapshot Name)
#   .\lab.ps1 zuruecksetzen    Alle VMs auf den Snapshot zuruecksetzen
# Hinweis: Diese Datei enthaelt absichtlich nur ASCII-Zeichen (keine Umlaute),
# damit Windows PowerShell 5.1 sie fehlerfrei liest.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('check', 'vorbereiten', 'erstellen', 'start', 'stop', 'status', 'snapshot', 'zuruecksetzen')]
    [string]$Aktion,
    [ValidateSet('11', '10')]
    [string]$Windows = '11',
    [string]$Snapshot = 'sauber',
    [string[]]$Nur
)

$ErrorActionPreference = 'Stop'
$Lab     = Split-Path -Parent $MyInvocation.MyCommand.Path
$VMBase  = Join-Path $Lab 'vms'
$IsoDir  = Join-Path $Lab 'iso'
$ImgDir  = Join-Path $Lab 'images'
$ShareDir = Join-Path $Lab 'share'
$Netz    = 'rcc-buero'

# --- VBoxManage finden ---
$Vbm = $null
foreach ($c in @("$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe", "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe")) {
    if (Test-Path $c) { $Vbm = $c; break }
}
if (-not $Vbm) {
    $cmd = Get-Command VBoxManage -ErrorAction SilentlyContinue
    if ($cmd) { $Vbm = $cmd.Source }
}
if (-not $Vbm) { throw 'VirtualBox nicht gefunden. Bitte Version 7.x von virtualbox.org installieren.' }

function VB {
    & $Vbm @args
    if ($LASTEXITCODE -ne 0) { throw ("VBoxManage fehlgeschlagen: " + ($args -join ' ')) }
}
function Invoke-Try {
    # Fuehrt VBoxManage aus, ohne bei einem Fehler abzubrechen. Gibt $true bei Erfolg zurueck.
    $alt = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $Vbm @args 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $alt
    return $ok
}
function Test-Vm([string]$n) {
    $liste = & $Vbm list vms
    return [bool]($liste | Where-Object { $_ -match ('^"' + [regex]::Escape($n) + '"') })
}
function Test-Running([string]$n) {
    $info = & $Vbm showvminfo $n --machinereadable
    return [bool]($info | Where-Object { $_ -match '^VMState="running"' })
}

# --- Ausstattung je nach Arbeitsspeicher des PCs ---
$ramGB  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$knapp  = $ramGB -lt 28
$VMs = @(
    @{ Name = 'rcc-wazuh';   RAM = $(if ($knapp) { 6144 } else { 8192 }); CPU = 4; Disk = 51200 },
    @{ Name = 'rcc-scanner'; RAM = $(if ($knapp) { 4096 } else { 6144 }); CPU = 2; Disk = 40960 },
    @{ Name = 'buero-pc1';   RAM = $(if ($knapp) { 3072 } else { 4096 }); CPU = 2; Disk = 61440 },
    @{ Name = 'buero-nas';   RAM = 512;                                   CPU = 1; Disk = 0 }
)
function Get-Ziele {
    $VMs | Where-Object { (-not $Nur) -or ($Nur -contains $_.Name) }
}

function New-Server($v, [string[]]$natpf) {
    $n = $v.Name
    $dir = Join-Path $VMBase $n
    $vdi = Join-Path $dir "$n.vdi"
    VB createvm --name $n --ostype Ubuntu_64 --register --basefolder $VMBase
    VB modifyvm $n --memory $v.RAM --cpus $v.CPU --ioapic on --graphicscontroller vmsvga --vram 16 --nic1 nat --nic2 intnet --intnet2 $Netz
    foreach ($r in $natpf) { VB modifyvm $n --natpf1 $r }
    VB storagectl $n --name SATA --add sata --controller IntelAhci --portcount 2
    VB createmedium disk --filename $vdi --size $v.Disk --format VDI
    VB storageattach $n --storagectl SATA --port 0 --device 0 --type hdd --medium $vdi
    $iso = Join-Path $IsoDir 'ubuntu.iso'
    if (Test-Path $iso) {
        VB storageattach $n --storagectl SATA --port 1 --device 0 --type dvddrive --medium $iso
    } else {
        Write-Host "  Hinweis: iso\ubuntu.iso fehlt - DVD-Laufwerk bleibt leer."
        VB storageattach $n --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
    }
    VB modifyvm $n --boot1 dvd --boot2 disk --boot3 none --boot4 none
}

function New-WindowsVm($v) {
    $n = $v.Name
    $dir = Join-Path $VMBase $n
    $vdi = Join-Path $dir "$n.vdi"
    if ($Windows -eq '11') { $os = 'Windows11_64' } else { $os = 'Windows10_64' }
    VB createvm --name $n --ostype $os --register --basefolder $VMBase
    VB modifyvm $n --memory $v.RAM --cpus $v.CPU --ioapic on --graphicscontroller vboxsvga --vram 128 --nic1 nat --nic2 intnet --intnet2 $Netz
    if ($Windows -eq '11') { VB modifyvm $n --firmware efi --tpm-type 2.0 }
    VB storagectl $n --name SATA --add sata --controller IntelAhci --portcount 2
    VB createmedium disk --filename $vdi --size $v.Disk --format VDI
    VB storageattach $n --storagectl SATA --port 0 --device 0 --type hdd --medium $vdi
    $iso = Join-Path $IsoDir 'windows.iso'
    if (Test-Path $iso) {
        VB storageattach $n --storagectl SATA --port 1 --device 0 --type dvddrive --medium $iso
    } else {
        Write-Host "  Hinweis: iso\windows.iso fehlt - DVD-Laufwerk bleibt leer."
        VB storageattach $n --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
    }
    VB modifyvm $n --boot1 dvd --boot2 disk --boot3 none --boot4 none
    # Gemeinsamer Ordner (nur lesen), wird nach Installation der Guest Additions sichtbar
    New-Item -ItemType Directory -Force $ShareDir | Out-Null
    VB sharedfolder add $n --name rcc-lab --hostpath $ShareDir --automount --readonly
}

function New-NasVm($v) {
    $n = $v.Name
    $dir = Join-Path $VMBase $n
    $quelle = Join-Path $ImgDir 'Metasploitable.vmdk'
    if (-not (Test-Path $quelle)) {
        Write-Host "  Hinweis: images\Metasploitable.vmdk fehlt - buero-nas wird uebersprungen (siehe LAB-ANLEITUNG.md)."
        return
    }
    $vdi = Join-Path $dir "$n.vdi"
    VB createvm --name $n --ostype Ubuntu --register --basefolder $VMBase
    # SICHERHEIT: nur das interne Netz, niemals NAT oder Bridge!
    VB modifyvm $n --memory $v.RAM --cpus $v.CPU --pae on --graphicscontroller vmsvga --vram 16 --nic1 intnet --intnet1 $Netz
    VB storagectl $n --name IDE --add ide
    VB clonemedium disk $quelle $vdi --format VDI
    VB storageattach $n --storagectl IDE --port 0 --device 0 --type hdd --medium $vdi
}

switch ($Aktion) {

    'check' {
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $laufwerk = $Lab.Substring(0, 1)
        $frei = [math]::Round((Get-PSDrive -Name $laufwerk).Free / 1GB)
        Write-Host "VirtualBox:          $(& $Vbm --version)"
        Write-Host "Arbeitsspeicher:     $ramGB GB"
        Write-Host "CPU-Threads:         $cpu"
        Write-Host "Freier Platz (${laufwerk}:):   $frei GB"
        if ($knapp) {
            Write-Host "-> Knapper Arbeitsspeicher: Profil 'knapp' (Wazuh 6 GB, Scanner 4 GB, Windows 3 GB)."
            Write-Host "   Nicht alle VMs gleichzeitig starten, siehe Anleitung."
        } else {
            Write-Host "-> Genug Arbeitsspeicher fuer alle 4 VMs gleichzeitig (ca. 19 GB)."
        }
        if ($frei -lt 100) { Write-Host "-> Achtung: Unter 100 GB frei. Das Labor braucht bis ca. 100 GB." }
        if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
            Write-Host "-> Hinweis: Hyper-V/WSL2/Docker Desktop ist aktiv. VirtualBox laeuft dann langsamer."
        }
        if (-not ((& $Vbm --version) -match '^7\.')) {
            Write-Host "-> Achtung: Diese Skripte sind fuer VirtualBox 7.x gedacht."
        }
    }

    'vorbereiten' {
        New-Item -ItemType Directory -Force $IsoDir, $ImgDir | Out-Null
        $dl = Join-Path $env:USERPROFILE 'Downloads'
        Write-Host "Suche in $dl ..."
        $isos = @(Get-ChildItem $dl -Filter *.iso -File -ErrorAction SilentlyContinue)

        $ub = $isos | Where-Object { $_.Name -match 'ubuntu' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $win = $isos | Where-Object { $_.Name -notmatch 'ubuntu' -and $_.Length -gt 3GB } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $zip = Get-ChildItem $dl -Filter *.zip -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'metasploitable' } | Select-Object -First 1
        $vmdk = Get-ChildItem $dl -Filter *.vmdk -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'metasploitable' } | Select-Object -First 1

        if ($ub) {
            Write-Host "Ubuntu:          $($ub.Name) -> iso\ubuntu.iso (Kopie)"
            Copy-Item $ub.FullName (Join-Path $IsoDir 'ubuntu.iso') -Force
        } else { Write-Host "Ubuntu:          NICHT gefunden (Datei mit 'ubuntu' im Namen und Endung .iso)" }

        if ($win) {
            Write-Host "Windows:         $($win.Name) -> iso\windows.iso (Kopie)"
            Copy-Item $win.FullName (Join-Path $IsoDir 'windows.iso') -Force
        } else { Write-Host "Windows:         NICHT gefunden (ISO groesser als 3 GB ohne 'ubuntu' im Namen)" }

        if ($vmdk) {
            Write-Host "Metasploitable:  $($vmdk.Name) -> images\Metasploitable.vmdk (Kopie)"
            Copy-Item $vmdk.FullName (Join-Path $ImgDir 'Metasploitable.vmdk') -Force
        } elseif ($zip) {
            Write-Host "Metasploitable:  $($zip.Name) wird entpackt ..."
            $tmp = Join-Path $env:TEMP 'rcc-msf2'
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            Expand-Archive $zip.FullName -DestinationPath $tmp -Force
            $v = Get-ChildItem $tmp -Filter *.vmdk -File -Recurse | Where-Object { $_.Name -notmatch 'flat' } | Select-Object -First 1
            if (-not $v) { $v = Get-ChildItem $tmp -Filter *.vmdk -File -Recurse | Select-Object -First 1 }
            if ($v) {
                Copy-Item $v.FullName (Join-Path $ImgDir 'Metasploitable.vmdk') -Force
                Write-Host "                 -> images\Metasploitable.vmdk"
            } else { Write-Host "                 keine .vmdk im ZIP gefunden" }
            Remove-Item $tmp -Recurse -Force
        } else { Write-Host "Metasploitable:  NICHT gefunden (optional, das NAS wird sonst uebersprungen)" }

        # ISOs in bereits angelegte VMs einlegen (VM muss ausgeschaltet sein)
        foreach ($paar in @(@('rcc-wazuh', 'ubuntu.iso'), @('rcc-scanner', 'ubuntu.iso'), @('buero-pc1', 'windows.iso'))) {
            $vmName = $paar[0]
            $isoPfad = Join-Path $IsoDir $paar[1]
            if ((Test-Path $isoPfad) -and (Test-Vm $vmName)) {
                if (Test-Running $vmName) { Write-Host "$vmName laeuft - ISO nicht eingelegt (erst ausschalten)."; continue }
                if (Invoke-Try storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium $isoPfad) {
                    Write-Host "ISO in $vmName eingelegt."
                } else { Write-Host "ISO in $vmName konnte nicht eingelegt werden." }
            }
        }
        if ((Test-Path (Join-Path $ImgDir 'Metasploitable.vmdk')) -and -not (Test-Vm 'buero-nas')) {
            Write-Host "buero-nas wird angelegt ..."
            $Nur = @('buero-nas')
            $v = Get-Ziele
            New-NasVm $v
        }

        Write-Host ""
        Write-Host "Fertig. Weiter mit:  .\lab.ps1 erstellen   (falls noch keine VMs da sind), sonst Ubuntu installieren."
    }

    'erstellen' {
        New-Item -ItemType Directory -Force $VMBase, $IsoDir, $ImgDir, $ShareDir | Out-Null

        Write-Host "Internes Netz '$Netz' mit DHCP (10.10.10.100-200) einrichten ..."
        $dhcpOk = Invoke-Try dhcpserver add --network=$Netz --server-ip=10.10.10.1 --netmask=255.255.255.0 --lower-ip=10.10.10.100 --upper-ip=10.10.10.200 --enable
        if (-not $dhcpOk) {
            VB dhcpserver modify --network=$Netz --server-ip=10.10.10.1 --netmask=255.255.255.0 --lower-ip=10.10.10.100 --upper-ip=10.10.10.200 --enable
        }

        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (Test-Vm $n) { Write-Host "$n existiert schon - uebersprungen."; continue }
            Write-Host "Erstelle $n ..."
            switch ($n) {
                'rcc-wazuh'   { New-Server $v @('ssh,tcp,127.0.0.1,2223,,22', 'wazuh,tcp,127.0.0.1,8443,,443') }
                'rcc-scanner' { New-Server $v @('ssh,tcp,127.0.0.1,2222,,22') }
                'buero-pc1'   { New-WindowsVm $v }
                'buero-nas'   { New-NasVm $v }
            }
        }
        Write-Host ""
        Write-Host "Fertig. Naechster Schritt: Ubuntu auf rcc-wazuh und rcc-scanner installieren (siehe LAB-ANLEITUNG.md)."
    }

    'start' {
        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (-not (Test-Vm $n)) { Write-Host "$n gibt es nicht - uebersprungen."; continue }
            if (Test-Running $n) { Write-Host "$n laeuft schon."; continue }
            if ($n -eq 'buero-pc1') { $typ = 'gui' } else { $typ = 'headless' }
            Write-Host "Starte $n ($typ) ..."
            VB startvm $n --type $typ
        }
    }

    'stop' {
        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (-not (Test-Vm $n)) { continue }
            if (-not (Test-Running $n)) { continue }
            Write-Host "Fahre $n herunter ..."
            if ($n -eq 'buero-nas') { VB controlvm $n poweroff } else { VB controlvm $n acpipowerbutton }
        }
    }

    'status' {
        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (-not (Test-Vm $n)) { Write-Host ("{0,-12} nicht erstellt" -f $n); continue }
            $zustand = 'aus'
            if (Test-Running $n) { $zustand = 'LAEUFT' }
            Write-Host ("{0,-12} {1,-8} {2} MB RAM, {3} CPU" -f $n, $zustand, $v.RAM, $v.CPU)
        }
    }

    'snapshot' {
        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (-not (Test-Vm $n)) { continue }
            Write-Host "Snapshot '$Snapshot' fuer $n ..."
            $null = Invoke-Try snapshot $n delete $Snapshot
            VB snapshot $n take $Snapshot
        }
    }

    'zuruecksetzen' {
        foreach ($v in Get-Ziele) {
            $n = $v.Name
            if (-not (Test-Vm $n)) { continue }
            if (Test-Running $n) { VB controlvm $n poweroff; Start-Sleep -Seconds 3 }
            Write-Host "Setze $n auf Snapshot '$Snapshot' zurueck ..."
            VB snapshot $n restore $Snapshot
        }
    }
}

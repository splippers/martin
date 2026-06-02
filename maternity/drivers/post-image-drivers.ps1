<#
.SYNOPSIS
    M.A.R.T.I.N. — Post-Imaging Driver Population
    Runs on freshly imaged device. Detects model, mounts Samba share,
    installs missing/updated drivers from the Dell Driver Cache.
.DESCRIPTION
    Designed to run as a FOG post-download script or manually after imaging.
    Queries WMI for the Dell model, mounts the read-only driver share,
    scans for missing or outdated drivers, and installs the latest.
.PARAMETER DriverServer
    Samba server hostname or IP (default: 192.168.88.99)
.PARAMETER ShareName
    Samba share name (default: DellDrivers)
.PARAMETER LogDir
    Log output directory (default: C:\BitzNBobz\drivers)
#>

param(
    [string]$DriverServer = "192.168.88.99",
    [string]$ShareName = "DellDrivers",
    [string]$LogDir = "C:\BitzNBobz\drivers"
)

$ErrorActionPreference = "Stop"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Hostname = $env:COMPUTERNAME

# Ensure admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run as Administrator. Exiting."
    exit 1
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Start-Transcript -Path "$LogDir\driver-install-$Timestamp.log"
Write-Host "=== M.A.R.T.I.N. Post-Imaging Driver Population ===" -ForegroundColor Cyan

# ── 1. Detect Model ───────────────────────────────────────────────────

Write-Host "[1/5] Detecting hardware model..."
$CS = Get-CimInstance Win32_ComputerSystem
$Model = $CS.Model.Trim()
$Manufacturer = $CS.Manufacturer.Trim()

if ($Manufacturer -notmatch "Dell") {
    Write-Warning "Not a Dell system ($Manufacturer). Driver cache only supports Dell."
    Write-Host "Skipping driver installation." -ForegroundColor Yellow
    exit 0
}

# Normalize model name for directory lookup
$ModelDir = $Model -replace '\s+', '_' -replace '[^a-zA-Z0-9_-]', ''
Write-Host "  Model: $Model → $ModelDir"

# ── 2. Mount Driver Share ─────────────────────────────────────────────

Write-Host "[2/5] Mounting driver share..."
$SharePath = "\\$DriverServer\$ShareName"
$MountPoint = "D:\Drivers"

if (-not (Test-Path $MountPoint)) {
    New-Item -ItemType Directory -Force -Path $MountPoint | Out-Null
}

# Map drive
$DriveLetter = "D:"
try {
    net use $DriveLetter $SharePath /persistent:no 2>&1 | Out-Null
    Write-Host "  Mapped $SharePath to $DriveLetter"
} catch {
    Write-Warning "  Failed to mount share: $_"
    Write-Host "  Attempting direct UNC access..."
}

$ModelDrivers = "$DriveLetter\$ModelDir"
$AlternateDrivers = "\\$DriverServer\$ShareName\$ModelDir"

if (Test-Path $ModelDrivers) {
    $DriverSource = $ModelDrivers
    Write-Host "  Driver path: $ModelDrivers"
} elseif (Test-Path $AlternateDrivers) {
    $DriverSource = "\\$DriverServer\$ShareName\$ModelDir"
    Write-Host "  Driver path (UNC): $DriverSource"
} else {
    Write-Warning "  No drivers found for $ModelDir on $ShareName"
    Write-Host "  Check the driver cache has been populated for this model."
    Write-Host "  Server: $DriverServer, Share: $ShareName, Model: $ModelDir"
    net use $DriveLetter /delete 2>&1 | Out-Null
    exit 1
}

# ── 3. Scan for Missing/Outdated Drivers ──────────────────────────────

Write-Host "[3/5] Scanning for missing and outdated drivers..."
$InstalledDrivers = @{}
try {
    $DrvQuery = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -and $_.DriverVersion }
    foreach ($D in $DrvQuery) {
        $Key = "$($D.DeviceName)|$($D.DeviceID)"
        $InstalledDrivers[$Key] = @{
            Name    = $D.DeviceName
            Version = $D.DriverVersion
            Date    = $D.DriverDate
            Provider = $D.DriverProviderName
        }
    }
    Write-Host "  Found $($InstalledDrivers.Count) installed drivers"
} catch {
    Write-Warning "  Driver scan failed: $_"
}

# ── 4. Install Drivers ───────────────────────────────────────────────

Write-Host "[4/5] Installing drivers from cache..."
$Installed = 0
$Skipped = 0
$Failed = 0
$InstallLog = @()

# Get all .inf files from the driver cache (recursive)
$DriverInfs = Get-ChildItem $DriverSource -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue
Write-Host "  Found $($DriverInfs.Count) driver packages in cache"

foreach ($Inf in $DriverInfs) {
    $InfPath = $Inf.FullName
    $PnpResult = pnputil /enum-drivers 2>&1 | Out-String

    # Quick check: is this driver already installed?
    $InfName = $Inf.Name
    if ($PnpResult -match [Regex]::Escape($InfName)) {
        $Skipped++
        continue
    }

    # Add the driver package
    Write-Host "    Installing: $($Inf.Directory.Name)\$InfName ..." -NoNewline
    try {
        $Result = pnputil /add-driver "$InfPath" /install 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $Result -match 'successfully installed|already installed') {
            Write-Host " OK" -ForegroundColor Green
            $Installed++
            $InstallLog += [PSCustomObject]@{
                inf   = $InfPath
                status = "installed"
                result = ($Result -split "`r`n" | Where-Object { $_ -match 'Published|Installed' }) -join "; "
            }
        } else {
            Write-Host " FAILED" -ForegroundColor Red
            $Failed++
            $InstallLog += [PSCustomObject]@{
                inf   = $InfPath
                status = "failed"
                result = ($Result -split "`r`n" | Where-Object { $_ -match 'error|fail' }) -join "; "
            }
        }
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
        $Failed++
        $InstallLog += [PSCustomObject]@{
            inf    = $InfPath
            status = "error"
            result = $_.Exception.Message
        }
    }
}

# Alternative: use pnputil to install by category
# For each category directory, install all .inf files
$CategoryDirs = Get-ChildItem $DriverSource -Directory -ErrorAction SilentlyContinue
foreach ($CatDir in $CategoryDirs) {
    $CatName = $CatDir.Name
    Write-Host "  Category: $CatName"

    $CatInfs = Get-ChildItem $CatDir.FullName -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue
    foreach ($Inf in $CatInfs) {
        $InfPath = $Inf.FullName
        try {
            $Result = pnputil /add-driver "$InfPath" /install 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -or $Result -match 'successfully installed') {
                $Installed++
                Write-Host "    Installed: $($Inf.Name)" -ForegroundColor Green
            }
        } catch {
            $Failed++
        }
    }
}

# ── 5. Report ─────────────────────────────────────────────────────────

Write-Host "[5/5] Generating report..."
$Report = @{
    hostname         = $Hostname
    timestamp        = $Timestamp
    manufacturer     = $Manufacturer
    model            = $Model
    model_dir        = $ModelDir
    driver_source    = $DriverSource
    installed_new    = $Installed
    already_present  = $Skipped
    failed           = $Failed
    install_log      = $InstallLog
    report_version   = "1.0"
}

$ReportJson = $Report | ConvertTo-Json -Depth 5
$ReportPath = "$LogDir\driver-report-$Timestamp.json"
$ReportJson | Out-File $ReportPath -Encoding utf8

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        POST-IMAGING DRIVER POPULATION              ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║ Model : $($Model.PadRight(42)) ║" -ForegroundColor Cyan
Write-Host "║ Installed : $Installed / Skipped : $Skipped / Failed : $Failed         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Report: $ReportPath" -ForegroundColor Green

# Cleanup mounted drive
net use $DriveLetter /delete 2>&1 | Out-Null

Stop-Transcript

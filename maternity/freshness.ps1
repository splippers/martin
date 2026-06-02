<#
.SYNOPSIS
    Maternity Freshness Assessment — Golden Image Quality Score
    Measures drift from upstream, bloat, and overall image health pre-sysprep.
.DESCRIPTION
    Runs inside the golden image VM before Sysprep.
    Compares installed components against online stable version manifests,
    assesses bloat, DISM health, and produces a JSON freshness report.

    Output: C:\BitzNBobz\freshness\<IMAGE_NAME>_<TIMESTAMP>\
.PARAMETER ImageName
    Name for this golden image build (e.g. "Latitude_5420_2026-Q2").
.PARAMETER OutputDir
    Output directory (default: C:\BitzNBobz\freshness).
.PARAMETER WingetCheck
    Enable winget upgrade scan (requires winget installed). Default: $true.
.PARAMETER MsUpdateCheck
    Enable Microsoft Update COM scan. Default: $true.
.PARAMETER BloatThresholdMB
    Threshold in MB for flagging bloat items. Default: 100.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ImageName,
    [string]$OutputDir = "C:\BitzNBobz\freshness",
    [switch]$SkipWinget = $false,
    [switch]$SkipMsUpdate = $false,
    [switch]$SkipDriverCheck = $false,
    [int]$BloatThresholdMB = 100
)

$ErrorActionPreference = "Stop"
$Hostname = $env:COMPUTERNAME
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = Join-Path $OutputDir "$ImageName`_$Timestamp"

# Ensure admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run as Administrator. Exiting."
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Start-Transcript -Path "$OutDir\freshness.log" -Append

Write-Host "=== Maternity Freshness Assessment ===" -ForegroundColor Cyan
Write-Host "Image : $ImageName"
Write-Host "Host  : $Hostname"
Write-Host "Time  : $Timestamp"
Write-Host "Output: $OutDir"
Write-Host ""

# ── Helper functions ──────────────────────────────────────────────────

function Score {
    param([int]$Value, [int]$Max, [int]$Ideal = $Max)
    [Math]::Max(0, [Math]::Min(100, [int]((($Ideal - $Value) / [Math]::Max(1, $Ideal)) * 100))))
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-RegistryValue {
    param([string]$Path, [string]$Value)
    try {
        return (Get-ItemProperty -Path $Path -Name $Value -ErrorAction Stop).$Value
    } catch { return $null }
}

# ── 1. System Baseline ────────────────────────────────────────────────

Write-Host "[1/8] System baseline..."
$OS = Get-CimInstance Win32_OperatingSystem
$CS = Get-CimInstance Win32_ComputerSystem
$BIOS = Get-CimInstance Win32_BIOS

$Baseline = [PSCustomObject]@{
    hostname        = $Hostname
    image_name      = $ImageName
    timestamp       = $Timestamp
    os_name         = $OS.Caption
    os_version      = $OS.Version
    os_build        = $OS.BuildNumber
    os_arch         = $OS.OSArchitecture
    install_date    = $OS.InstallDate
    last_boot       = $OS.LastBootUpTime
    manufacturer    = $CS.Manufacturer
    model           = $CS.Model
    total_ram_gb    = [int]($CS.TotalPhysicalMemory / 1GB)
    bios_serial     = $BIOS.SerialNumber
    bios_version    = $BIOS.SMBIOSBIOSVersion
}

# ── 2. Windows Update Drift ───────────────────────────────────────────

Write-Host "[2/8] Checking Windows Update drift..."
$WUResults = @()
$WUScore = 100
$WURemaining = 0
$WUCritical = 0

if (-not $SkipMsUpdate) {
    try {
        $UpdateSession = New-Object -ComObject Microsoft.Update.Session
        $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
        $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software' and AutoSelectOnWebSites=1")

        Write-Host "  Found $($SearchResult.Updates.Count) available updates"
        $WURemaining = $SearchResult.Updates.Count
        $WUCritical = ($SearchResult.Updates | Where-Object { $_.MsrcSeverity -eq "Critical" -or $_.MsrcSeverity -eq "Important" }).Count

        foreach ($Update in $SearchResult.Updates) {
            $WUResults += [PSCustomObject]@{
                title      = $Update.Title
                kb         = if ($Update.Title -match 'KB(\d+)') { "KB$($matches[1])" } else { "N/A" }
                severity   = $Update.MsrcSeverity
                size_mb    = [int]($Update.MaxDownloadSize / 1MB)
                is_mandatory = $Update.IsMandatory
            }
        }

        $WUScore = Score -Value $WURemaining -Max 50 -Ideal 0
        if ($WUCritical -gt 0) { $WUScore = [Math]::Max(0, $WUScore - ($WUCritical * 15)) }
    } catch {
        Write-Warning "  Windows Update scan failed: $_"
        $WUScore = $null
    }
} else {
    Write-Host "  Skipped (SkipMsUpdate flag)"
}

# ── 3. Application Freshness (Winget) ─────────────────────────────────

Write-Host "[3/8] Checking application freshness via winget..."
$AppResults = @()
$AppScore = 100
$AppsOutdated = 0
$AppsTotal = 0

if (-not $SkipWinget) {
    try {
        $WingetPath = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($WingetPath) {
            $UpgradeRaw = winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String
            $UpgradeLines = $UpgradeRaw -split "`r`n|`n"

            $Parsing = $false
            $HeaderPassed = $false
            foreach ($Line in $UpgradeLines) {
                if ($Line -match '^\s+Name\s+Id\s+Version\s+Available\s+Source') { $Parsing = $true; $HeaderPassed = $false; continue }
                if ($Parsing -and $Line -match '^-+\s+-+\s+-+\s+-+\s+-+') { if ($HeaderPassed) { $Parsing = $false }; $HeaderPassed = $true; continue }
                if ($Parsing -and $Line -match '^\S' -and $Line.Trim().Length -gt 10) {
                    $Parts = $Line -split '\s{2,}'
                    if ($Parts.Count -ge 4) {
                        $AppsOutdated++
                        $AppResults += [PSCustomObject]@{
                            name      = $Parts[0].Trim()
                            id        = $Parts[1].Trim()
                            installed = $Parts[2].Trim()
                            available = $Parts[3].Trim()
                            source    = if ($Parts.Count -ge 5) { $Parts[4].Trim() } else { "" }
                        }
                    }
                }
            }
            $InstalledRaw = winget list --accept-source-agreements 2>&1 | Out-String
            $AppsTotal = ($InstalledRaw -split "`r`n|`n" | Where-Object { $_ -match '^\S' -and $_ -notmatch '^Name\s+Id' -and $_ -notmatch '^---' }).Count

            Write-Host "  $AppsOutdated of $AppsTotal apps outdated"
            $AppScore = if ($AppsTotal -gt 0) { [Math]::Max(0, 100 - [int](($AppsOutdated / $AppsTotal) * 100)) } else { $null }
        } else {
            Write-Host "  winget not found on this image"
            $AppScore = $null
        }
    } catch {
        Write-Warning "  Winget scan failed: $_"
        $AppScore = $null
    }
} else {
    Write-Host "  Skipped (SkipWinget flag)"
}

# ── 4. Driver Freshness ───────────────────────────────────────────────

Write-Host "[4/8] Checking driver freshness..."
$DriverResults = @()
$DriverScore = 100
$DriversOutdated = 0

if (-not $SkipDriverCheck) {
    try {
        $DriversCsv = driverquery /v /fo csv 2>&1
        $Drivers = $DriversCsv | ConvertFrom-Csv -ErrorAction SilentlyContinue
        if ($Drivers) {
            $Now = Get-Date
            $DaysThreshold = 365
            $DriverTotal = 0
            foreach ($D in $Drivers) {
                $DriverTotal++
                $LinkDate = if ($D.'Link Date' -and $D.'Link Date' -match '\d{4}') {
                    try { [DateTime]::ParseExact($D.'Link Date', 'dd/MM/yyyy', $null) } catch { $null }
                } else { $null }
                $DriverDate = if ($D.'Driver Date' -and $D.'Driver Date' -match '\d{4}') {
                    try { [DateTime]::ParseExact($D.'Driver Date', 'dd/MM/yyyy', $null) } catch { $null }
                } else { $null }
                $EffDate = $LinkDate ?? $DriverDate
                if ($EffDate -and (($Now - $EffDate).TotalDays -gt $DaysThreshold)) {
                    $DriversOutdated++
                    $DriverResults += [PSCustomObject]@{
                        module_name    = $D.'Module Name'
                        display_name   = $D.'Display Name'
                        driver_date    = $D.'Driver Date'
                        driver_version = $D.'Driver Version'
                        age_days       = [int](($Now - $EffDate).TotalDays)
                        provider       = $D.'Provider Name'
                    }
                }
            }
            Write-Host "  $DriversOutdated of $DriverTotal drivers >1yr old"
            $DriverScore = if ($DriverTotal -gt 0) { [Math]::Max(0, 100 - [int](($DriversOutdated / $DriverTotal) * 100)) } else { $null }
        } else {
            Write-Host "  Unable to parse driver list"
            $DriverScore = $null
        }
    } catch {
        Write-Warning "  Driver scan failed: $_"
        $DriverScore = $null
    }
} else {
    Write-Host "  Skipped (SkipDriverCheck flag)"
}

# ── 5. Bloat Assessment ───────────────────────────────────────────────

Write-Host "[5/8] Assessing bloat..."
$BloatItems = @{}
$TotalWasteGB = 0.0

# Temp files
$TempPaths = @(
    "$env:TEMP",
    "$env:WINDIR\Temp",
    "$env:WINDIR\Prefetch",
    "$env:WINDIR\SoftwareDistribution\Download",
    "$env:LOCALAPPDATA\Temp"
)
$TempSize = 0
foreach ($Path in $TempPaths) {
    if (Test-Path $Path) {
        try {
            $Size = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $TempSize += $Size
        } catch {}
    }
}
$BloatItems["temp_files"] = @{ path = "Temp files (all locations)"; size_bytes = $TempSize; size_display = Format-Bytes $TempSize }
$TotalWasteGB += $TempSize / 1GB

# WinSxS store
$WinSxSPath = "$env:WINDIR\WinSxS"
if (Test-Path $WinSxSPath) {
    try {
        $DismSizeRaw = dism /online /english /Get-Size /LimitAccess 2>&1 | Out-String
        if ($DismSizeRaw -match 'Total size of component store:\s+([\d.]+)\s*MB') {
            $WinSxSSizeMB = [double]$matches[1]
            $BloatItems["winsxs"] = @{ path = "WinSxS component store"; size_bytes = [long]($WinSxSSizeMB * 1MB); size_display = "$([int]$WinSxSSizeMB) MB" }
            $TotalWasteGB += $WinSxSSizeMB / 1024
        }
    } catch {}
}

# Recycle Bin
try {
    $RbSize = (Get-ChildItem 'C:\$Recycle.Bin' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $BloatItems["recycle_bin"] = @{ path = "Recycle Bin"; size_bytes = $RbSize; size_display = Format-Bytes $RbSize }
    $TotalWasteGB += $RbSize / 1GB
} catch {}

# Orphan user profiles
try {
    $ProfilePath = "C:\Users"
    $CurrentUser = $env:USERNAME
    $OtherProfiles = Get-ChildItem $ProfilePath -Directory | Where-Object { $_.Name -ne $CurrentUser -and $_.Name -ne 'Public' -and $_.Name -ne 'Default' -and $_.Name -ne 'Default User' }
    $ProfileSize = 0
    $ProfileNames = @()
    foreach ($Prof in $OtherProfiles) {
        $PSize = (Get-ChildItem $Prof.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $ProfileSize += $PSize
        $ProfileNames += $Prof.Name
    }
    if ($ProfileSize -gt 0) {
        $BloatItems["orphan_profiles"] = @{ path = "Orphan user profiles: $($ProfileNames -join ', ')"; size_bytes = $ProfileSize; size_display = Format-Bytes $ProfileSize }
        $TotalWasteGB += $ProfileSize / 1GB
    }
} catch {}

# NGEN cache
try {
    $NativeImgSize = (Get-ChildItem "$env:WINDIR\assembly" -Recurse -Include *.dll -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($NativeImgSize -gt 0) {
        $BloatItems["ngen_cache"] = @{ path = "Native Images (NGEN cache)"; size_bytes = $NativeImgSize; size_display = Format-Bytes $NativeImgSize }
        $TotalWasteGB += $NativeImgSize / 1GB
    }
} catch {}

# Driver store
try {
    $DriverStorePath = "$env:WINDIR\System32\DriverStore\FileRepository"
    $DriverStoreSize = (Get-ChildItem $DriverStorePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $BloatItems["driver_store"] = @{ path = "Driver store (FileRepository)"; size_bytes = $DriverStoreSize; size_display = Format-Bytes $DriverStoreSize }
    $TotalWasteGB += $DriverStoreSize / 1GB
} catch {}

# Startup items
$StartupItems = @()
try {
    $StartupFolders = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
        [Environment]::GetFolderPath("Startup")
    )
    foreach ($F in $StartupFolders) {
        if (Test-Path $F) {
            $StartupItems += Get-ChildItem $F -File | Select-Object Name
        }
    }
    try {
        $RegistryStartup = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        if ($RegistryStartup) {
            $RegistryStartup.PSObject.Properties | Where-Object { $_.Name -notmatch '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$' } | ForEach-Object {
                $StartupItems += [PSCustomObject]@{ Name = "$($_.Name) (HKLM)" }
            }
        }
    } catch {}
} catch {}
$BloatItems["startup_count"] = @{ count = $StartupItems.Count; items = $StartupItems.Name }

# ── 6. DISM Health ────────────────────────────────────────────────────

Write-Host "[6/8] DISM health check..."
$DismHealth = $true
$DismDetail = ""
try {
    $DismResult = dism /online /cleanup-image /checkhealth /english 2>&1 | Out-String
    $DismHealth = $DismResult -match 'No component store corruption detected'
    $DismDetail = ($DismResult -split "`r`n|`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 5) -join "`n"
    if (-not $DismHealth) {
        $DismHealth = ($DismResult -match 'The component store is repairable')
    }
    Write-Host "  DISM health: $(if($DismHealth){'OK'}else{'ISSUES FOUND'})"
} catch {
    Write-Warning "  DISM check failed: $_"
    $DismHealth = $null
}

# ── 7. Registry Size ──────────────────────────────────────────────────

Write-Host "[7/8] Checking registry size..."
$RegSizeTotal = 0
try {
    $RegFiles = Get-ChildItem "$env:WINDIR\System32\config" -File -ErrorAction SilentlyContinue
    $RegSizeTotal = ($RegFiles | Measure-Object Length -Sum).Sum
    $UserReg = "$env:USERPROFILE\ntuser.dat"
    if (Test-Path $UserReg) {
        $RegSizeTotal += (Get-Item $UserReg).Length
    }
    Write-Host "  Registry hive files: $(Format-Bytes $RegSizeTotal)"
} catch {}

# ── 8. Scoring & Report ───────────────────────────────────────────────

Write-Host "[8/8] Calculating freshness score..."

$Scores = @{}
$Scores["windows_updates"] = @{ score = $WUScore; remaining = $WURemaining; critical = $WUCritical; count = $WUResults.Count }
$Scores["applications"] = @{ score = $AppScore; outdated = $AppsOutdated; total = $AppsTotal }
$Scores["drivers"] = @{ score = $DriverScore; outdated = $DriversOutdated; total = if ($Drivers) {$Drivers.Count} else {0} }

# Bloat score
$OSDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$TotalDiskGB = [int]($OSDrive.Size / 1GB)
$BloatScore = [Math]::Max(0, 100 - [int](($TotalWasteGB / [Math]::Max(1, $TotalDiskGB)) * 100))
if ($StartupItems.Count -gt 10) { $BloatScore = [Math]::Max(0, $BloatScore - (($StartupItems.Count - 10) * 2)) }
$Scores["bloat"] = @{ score = $BloatScore; waste_gb = [Math]::Round($TotalWasteGB, 2); total_disk_gb = $TotalDiskGB; startup_count = $StartupItems.Count }

$DismScore = if ($DismHealth -eq $true) { 100 } elseif ($DismHealth -eq $false) { 0 } else { $null }
$Scores["dism_health"] = @{ score = $DismScore; healthy = $DismHealth }

# Registry size score
$RegScore = if ($RegSizeTotal -lt 500MB) { 100 } elseif ($RegSizeTotal -lt 1GB) { 70 } elseif ($RegSizeTotal -lt 2GB) { 40 } else { 10 }
$Scores["registry"] = @{ score = $RegScore; size_bytes = $RegSizeTotal; size_display = Format-Bytes $RegSizeTotal }

# Overall freshness (weighted average)
$Weights = @{
    windows_updates = 0.30
    applications    = 0.20
    drivers         = 0.15
    bloat           = 0.15
    dism_health     = 0.10
    registry        = 0.10
}
$OverallScore = 0
$TotalWeight = 0
foreach ($Key in $Weights.Keys) {
    $S = $Scores[$Key].score
    if ($S -ne $null) {
        $OverallScore += $S * $Weights[$Key]
        $TotalWeight += $Weights[$Key]
    }
}
if ($TotalWeight -gt 0) {
    $OverallScore = [Math]::Round($OverallScore / $TotalWeight)
} else {
    $OverallScore = $null
}

# ── Build Output ───────────────────────────────────────────────────────

$Report = @{
    freshness       = @{
        overall    = $OverallScore
        categories = $Scores
    }
    baseline        = $Baseline
    wu_scan         = $WUResults
    app_drift       = $AppResults
    driver_aged     = $DriverResults
    bloat_items     = $BloatItems
    dism_detail     = $DismDetail
    registry_size   = @{ bytes = $RegSizeTotal; display = Format-Bytes $RegSizeTotal }
    report_version  = "1.0"
    report_generated = (Get-Date -Format "o")
}

$ReportJson = $Report | ConvertTo-Json -Depth 10
$ReportJson | Out-File "$OutDir\freshness-report.json" -Encoding utf8

# Human-readable summary
$Summary = @"
=============================================
 MATERNITY FRESHNESS ASSESSMENT
=============================================
 Image  : $ImageName
 Host   : $Hostname
 Time   : $Timestamp
---------------------------------------------
 FRESHNESS SCORE: $OverallScore/100
---------------------------------------------
 Windows Updates: $(if($WUScore -ne $null){$WUScore}else{'N/A'})/100
   Pending: $WURemaining ($WUCritical critical)
 Applications: $(if($AppScore -ne $null){$AppScore}else{'N/A'})/100
   $AppsOutdated of $AppsTotal outdated
 Drivers: $(if($DriverScore -ne $null){$DriverScore}else{'N/A'})/100
   $DriversOutdated drivers >1yr old
 Bloat: $BloatScore/100
   Waste: $([Math]::Round($TotalWasteGB, 2)) GB, $($StartupItems.Count) startup items
 DISM Health: $(if($DismHealth -eq $true){'PASS'}elseif($DismHealth -eq $false){'FAIL'}else{'N/A'})
 Registry: $(if($RegScore -ne $null){$RegScore}else{'N/A'})/100 ($(Format-Bytes $RegSizeTotal))
=============================================
"@

$Summary | Out-File "$OutDir\freshness-summary.txt" -Encoding utf8
Write-Host $Summary

$Report | Export-Clixml -Path "$OutDir\freshness-report.xml"

Stop-Transcript
Write-Host "Freshness assessment complete." -ForegroundColor Green
Write-Host "Report     : $OutDir\freshness-report.json"
Write-Host "Summary    : $OutDir\freshness-summary.txt"

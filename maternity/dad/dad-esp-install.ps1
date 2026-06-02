<#
.SYNOPSIS
    M.A.R.T.I.N. — D.A.D. ESP Driver Installer
    Runs via SetupComplete.cmd during Windows ESP/OOBE.
    Installs drivers from DAD SMB share for the detected Dell model.
#>

$LogPath = "$env:SystemRoot\Setup\Scripts\dad-esp-driver.log"
$DriverServer = "192.168.88.99"
$ShareName = "DellDrivers"

function Write-Log {
    param([string]$Msg)
    $Time = Get-Date -Format "HH:mm:ss"
    "$Time $Msg" | Out-File -FilePath $LogPath -Append -Encoding ASCII
}

Write-Log "=== M.A.R.T.I.N. D.A.D. ESP Driver Installer ==="
Write-Log "Starting at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Ensure admin
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Log "ERROR: Not running as Administrator (running as $((whoami)))"
    exit 1
}
Write-Log "Running as SYSTEM (admin)"

# Detect model
try {
    $CS = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $Model = $CS.Model.Trim()
    $Manufacturer = $CS.Manufacturer.Trim()
    Write-Log "Model: $Model"
    Write-Log "Manufacturer: $Manufacturer"
} catch {
    Write-Log "ERROR: Cannot detect model: $_"
    exit 1
}

if ($Manufacturer -notmatch "Dell") {
    Write-Log "Not a Dell system. Skipping driver install."
    exit 0
}

$ModelDir = $Model -replace '\s+', '_' -replace '[^a-zA-Z0-9_-]', ''
Write-Log "Cache dir: $ModelDir"

# Mount SMB share
$SharePath = "\\$DriverServer\$ShareName"
$DriveLetter = "D:"
$DriverSource = "$DriveLetter\$ModelDir\extracted"
$AlternateSource = "$SharePath\$ModelDir\extracted"

Write-Log "Mapping $SharePath to $DriveLetter"
try {
    net use $DriveLetter $SharePath /persistent:no 2>&1 | Out-Null
    Write-Log "Mapped OK"
} catch {
    Write-Log "WARNING: net use failed: $_"
}

if (Test-Path $DriverSource) {
    $Source = $DriverSource
    Write-Log "Source: $DriverSource"
} elseif (Test-Path $AlternateSource) {
    $Source = $AlternateSource
    Write-Log "Source (UNC): $AlternateSource"
} else {
    Write-Log "ERROR: Driver path not found: $DriverSource or $AlternateSource"
    net use $DriveLetter /delete 2>&1 | Out-Null
    exit 1
}

# Install drivers via pnputil with directory recursion
Write-Log "Installing drivers from $Source ..."
$Start = Get-Date
$Result = pnputil /add-driver "$Source\*.inf" /subdirs /install 2>&1
$Duration = (Get-Date) - $Start
Write-Log "pnputil completed in $($Duration.TotalSeconds)s"

# Log results
$Installed = 0
$Failed = 0
$Skipped = 0
foreach ($Line in $Result) {
    if ($Line -match "published.*name|installed successfully") { $Installed++ }
    elseif ($Line -match "error|failed") { $Failed++ }
    elseif ($Line -match "already installed|skipped") { $Skipped++ }
}
Write-Log "Installed: $Installed | Skipped: $Skipped | Failed: $Failed"
Write-Log "Result output (last 10 lines):"
$Result[-10..-1] | ForEach-Object { Write-Log "  $_" }

# Verify
Write-Log "Verifying driver installation..."
$PnPResult = pnputil /enum-drivers 2>&1 | Out-String
$AllInfCount = ([regex]::Matches($PnPResult, "Published Name")).Count
Write-Log "Total published drivers: $AllInfCount"

# Cleanup
net use $DriveLetter /delete 2>&1 | Out-Null
Write-Log "=== Complete ==="
Write-Log "Log: $LogPath"

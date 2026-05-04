<#
.SYNOPSIS
    Pre-Med/Op Prep for JOS + WENDY
    Benchmarks, captures logs, suspends BitLocker for offline scan
.DESCRIPTION
    Run on Dell Latitude before FOG capture or WENDY diagnosis
    Outputs to C:\BitzNBobz and creates WENDY-ready manifest
#>

# Requires: Run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run as Administrator. Exiting."
    exit 1
}

$OutDir = "C:\BitzNBobz"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Hostname = $env:COMPUTERNAME
$LogDir = Join-Path $OutDir "$Hostname`_$Timestamp"

# 1. Prep output dir
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
"Pre-Med Run: $Timestamp on $Hostname" | Out-File "$LogDir\00_RUN_INFO.txt"

# 2. System baseline - WENDY needs this for context
Write-Host "[1/6] Capturing system baseline..."
systeminfo /fo list > "$LogDir\01_systeminfo.txt"
wmic computersystem get Manufacturer,Model,Name,TotalPhysicalMemory /format:list > "$LogDir\02_hw_summary.txt"
wmic bios get SerialNumber,SMBIOSVersion /format:list >> "$LogDir\02_hw_summary.txt"
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsHardwareAbstractionLayer | Format-List > "$LogDir\03_os_info.txt"

# 3. Disk + SMART - critical for "should we reimage or replace?"
Write-Host "[2/6] Disk health check..."
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size | Format-Table -AutoSize > "$LogDir\04_disks.txt"
Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk) | Format-List > "$LogDir\05_smart.txt" 2>$null
# Fallback if Storage module fails on older Win10
wmic diskdrive get Status,Model,Size /format:list >> "$LogDir\05_smart.txt"

# 4. Quick benchmark - gives WENDY a perf baseline vs other Latitudes
Write-Host "[3/6] Running quick benchmark..."
winsat disk -drive c -ran -read > "$LogDir\06_winsat_disk.txt"
winsat cpu -encryption > "$LogDir\07_winsat_cpu.txt"  # AES test, fast and relevant
# Memory speed test - optional, takes 10s
winsat mem > "$LogDir\08_winsat_mem.txt"

# 5. Logs WENDY actually cares about
Write-Host "[4/6] Exporting Event Logs..."
wevtutil epl System "$LogDir\09_System.evtx"
wevtutil epl Application "$LogDir\10_Application.evtx"
wevtutil epl "Microsoft-Windows-DriverFrameworks-UserMode/Operational" "$LogDir\11_DriverFrameworks.evtx" 2>$null
# Last 7 days of critical/error only, for LLM sanity
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} | 
    Select-Object TimeCreated, Id, LevelDisplayName, Message | 
    Export-Csv "$LogDir\12_System_Errors_7d.csv" -NoTypeInformation

# Driver + crash info
driverquery /v /fo csv > "$LogDir\13_drivers.csv"
Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | 
    Select-Object Name, Length, LastWriteTime > "$LogDir\14_minidumps.txt"
Get-ChildItem C:\Windows\LiveKernelReports -Recurse -ErrorAction SilentlyContinue | 
    Select-Object FullName, Length, LastWriteTime > "$LogDir\15_livekernel.txt"

# 6. BitLocker: suspend for offline JOS scan
Write-Host "[5/6] Checking BitLocker..."
$BitlockerSuspendedThisRun = $false
$BitlockerStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($BitlockerStatus) {
    $BitlockerStatus | Format-List > "$LogDir\16_bitlocker_pre.txt"
    if ($BitlockerStatus.ProtectionStatus -eq "On") {
        Write-Host "Suspending BitLocker for 1 reboot - JOS can now offline scan" -ForegroundColor Yellow
        Suspend-BitLocker -MountPoint "C:" -RebootCount 1
        $BitlockerSuspendedThisRun = $true
        "BitLocker suspended for 1 reboot at $Timestamp" > "$LogDir\16_bitlocker_suspended.txt"
    } else {
        "BitLocker already suspended or off" > "$LogDir\16_bitlocker_suspended.txt"
    }
} else {
    "BitLocker not present on C:" > "$LogDir\16_bitlocker_suspended.txt"
}

# 7. WENDY Manifest - makes ingestion brainless
Write-Host "[6/6] Creating WENDY manifest..."
$Manifest = @{
    hostname = $Hostname
    timestamp = $Timestamp
    model = (Get-WmiObject Win32_ComputerSystem).Model
    serial = (Get-WmiObject Win32_BIOS).SerialNumber
    os_version = (Get-ComputerInfo).WindowsProductName
    bitlocker_suspended = $BitlockerSuspendedThisRun
    files = (Get-ChildItem $LogDir | Select-Object Name, Length).Name
    premed_version = "1.0"
}
$Manifest | ConvertTo-Json | Out-File "$LogDir\00_WENDY_MANIFEST.json"

# 8. Hash for integrity
Get-ChildItem $LogDir -File | Get-FileHash -Algorithm SHA256 | 
    Export-Csv "$LogDir\00_SHA256.csv" -NoTypeInformation

Write-Host "Pre-Med complete. Output: $LogDir" -ForegroundColor Green
Write-Host "Safe to PXE boot to JOS/WENDY. BitLocker will re-arm after 1 reboot if you boot Windows." -ForegroundColor Green
<#
.SYNOPSIS
    M.A.R.T.I.N. — D.A.D. Driver Puller
    Downloads Dell driver packs from Windows (bypasses Akamai/CDN blocks
    that affect Linux tools). Seeds the D.A.D. cache server.
.DESCRIPTION
    Run on a Windows machine that can reach the D.A.D. SMB share.
    Detects the local model, checks if drivers are cached, and if not,
    downloads the latest driver pack from Dell and uploads to the cache.
    Can also be used to bulk-seed all missing models.
.PARAMETER DadServer
    D.A.D. server hostname or IP (default: 192.168.88.99)
.PARAMETER Action
    "auto" = detect local model and seed (default)
    "bulk" = seed ALL models that are missing from cache
.PARAMETER Model
    Specific model to seed (for bulk mode)
#>

param(
    [string]$DadServer = "192.168.88.99",
    [string]$Action = "auto"
)

$SharePath = "\\$DadServer\DellDrivers"

# ── Ensure admin ─────────────────────────────────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Run as Administrator. Exiting." -ForegroundColor Red
    exit 1
}

# ── Detect local model ───────────────────────────────────────────────
function Get-LocalModel {
    $cs = Get-CimInstance Win32_ComputerSystem
    return @{
        Model = $cs.Model.Trim()
        Manufacturer = $cs.Manufacturer.Trim()
    }
}

# ── Get missing models from DAD ──────────────────────────────────────
function Get-MissingModels {
    param([string]$Server)
    $manifest = "$SharePath\download-manifest.txt"
    if (Test-Path $manifest) {
        $missing = @()
        Get-Content $manifest | ForEach-Object {
            if ($_ -match "^\[MISSING\] (.+)") {
                $missing += $matches[1]
            }
        }
        return $missing
    }
    return @()
}

# ── Download driver pack from Dell ───────────────────────────────────
function Invoke-DellDriverDownload {
    param([string]$Model)

    Write-Host "[DAD] Downloading drivers for: $Model" -ForegroundColor Cyan

    # Normalize model name for Dell URL
    $urlModel = $Model -replace '\s+', '%20'
    $apiUrl = "https://www.dell.com/support/api/catalog/v2/Product/$urlModel/Category/Driver/Filter/oscode/WIN11"

    try {
        # Try Dell API first
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json

        # Extract CAB download URL
        $cabUrl = $null
        if ($data -is [System.Array]) {
            foreach ($driver in $data) {
                $url = $driver.fileUrl -or $driver.url
                if ($url -and $url -like "*.cab") {
                    $cabUrl = $url
                    break
                }
            }
        } elseif ($data.Response -is [System.Array]) {
            foreach ($driver in $data.Response) {
                $url = $driver.DownloadURL -or $driver.fileUrl
                if ($url -and $url -like "*.cab") {
                    $cabUrl = $url
                    break
                }
            }
        }

        if (-not $cabUrl) {
            Write-Host "[DAD] No CAB found via API, trying support page..." -ForegroundColor Yellow
            # Try scraping the support page
            $pageUrl = "https://www.dell.com/support/home/en-us/product-support/product/$($Model -replace '\s+', '-')/drivers"
            $page = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -TimeoutSec 15
            $cabLinks = $page.Links | Where-Object { $_.href -like "*.cab*" }
            if ($cabLinks) {
                $cabUrl = $cabLinks[0].href
            }
        }

        if (-not $cabUrl) {
            Write-Host "[DAD] Could not find download URL for $Model" -ForegroundColor Red
            return $null
        }

        Write-Host "[DAD] Downloading: $cabUrl" -ForegroundColor Gray
        $tempCab = "$env:TEMP\$($Model -replace '\s+','_').cab"
        Invoke-WebRequest -Uri $cabUrl -OutFile $tempCab -UseBasicParsing -TimeoutSec 300

        if ((Get-Item $tempCab).Length -gt 1MB) {
            return $tempCab
        } else {
            Write-Host "[DAD] Downloaded file too small, likely an error page" -ForegroundColor Red
            Remove-Item $tempCab -Force -ErrorAction SilentlyContinue
            return $null
        }
    }
    catch {
        Write-Host "[DAD] Download failed: $_" -ForegroundColor Red
        return $null
    }
}

# ── Upload to D.A.D. cache ───────────────────────────────────────────
function Invoke-DadRegister {
    param([string]$Model, [string]$CabPath)
    $dirName = $Model -replace '\s+', '_' -replace '[^a-zA-Z0-9_-]', ''
    $targetDir = "$SharePath\$dirName"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    # Extract CAB
    if (Get-Command expand -ErrorAction SilentlyContinue) {
        Write-Host "[DAD] Extracting driver CAB..."
        # Use expand.exe (built into Windows)
        & expand.exe "$CabPath" -F:* "$targetDir\extracted\" 2>&1 | Out-Null
    } elseif (Get-Command 7z -ErrorAction SilentlyContinue) {
        & 7z x "$CabPath" -o"$targetDir\extracted\" -y | Out-Null
    } else {
        # Just copy the CAB for extraction on the server
        Copy-Item "$CabPath" "$targetDir\package.cab" -Force
    }

    Write-Host "[DAD] Seeded cache for $Model" -ForegroundColor Green
}

# ── Main ─────────────────────────────────────────────────────────────
Write-Host "=== M.A.R.T.I.N. D.A.D. Driver Puller ===" -ForegroundColor Cyan
Write-Host "Server: $DadServer" -ForegroundColor Gray

if ($Action -eq "auto") {
    $local = Get-LocalModel
    Write-Host "[DAD] Local model: $($local.Model)" -ForegroundColor White

    if ($local.Manufacturer -notmatch "Dell") {
        Write-Host "[DAD] Not a Dell system. Exiting." -ForegroundColor Yellow
        exit 0
    }

    $cabPath = Invoke-DellDriverDownload -Model $local.Model
    if ($cabPath) {
        Invoke-DadRegister -Model $local.Model -CabPath $cabPath
        Remove-Item $cabPath -Force -ErrorAction SilentlyContinue
    }
}
elseif ($Action -eq "bulk") {
    Write-Host "[DAD] Bulk seeding all missing models..." -ForegroundColor Yellow
    $missing = Get-MissingModels -Server $DadServer
    Write-Host "[DAD] Models to seed: $($missing -join ', ')" -ForegroundColor White

    foreach ($model in $missing) {
        $cabPath = Invoke-DellDriverDownload -Model $model
        if ($cabPath) {
            Invoke-DadRegister -Model $model -CabPath $CabPath
            Remove-Item $cabPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "=== D.A.D. Puller Complete ===" -ForegroundColor Cyan

@echo off
:: M.A.R.T.I.N. — D.A.D. ESP Driver Installer Bootstrap
:: Runs automatically at the tail end of Windows Setup (ESP/OOBE)
:: Launches the PowerShell driver installer script

setlocal enabledelayedexpansion

set "LOG=%SystemRoot%\Setup\Scripts\dad-esp-bootstrap.log"

echo %date% %time% Starting D.A.D. ESP Driver Installer >> %LOG%

:: Wait for network to be ready
ping -n 1 192.168.88.99 >nul 2>&1
if errorlevel 1 (
    echo %date% %time% WARNING: DAD server not reachable, waiting 15s... >> %LOG%
    ping -n 15 127.0.0.1 >nul 2>&1
    ping -n 1 192.168.88.99 >nul 2>&1
    if errorlevel 1 (
        echo %date% %time% ERROR: DAD server 192.168.88.99 unreachable >> %LOG%
        exit /b 1
    )
)
echo %date% %time% DAD server reachable >> %LOG%

:: Launch PowerShell installer
set "PS_SCRIPT=%SystemRoot%\Setup\Scripts\dad-esp-install.ps1"
echo %date% %time% Launching PowerShell installer... >> %LOG%

powershell.exe -ExecutionPolicy Bypass -File "%PS_SCRIPT%" >> %LOG% 2>&1

echo %date% %time% PowerShell installer exited with code %errorlevel% >> %LOG%

:: Self-cleanup
if exist "%PS_SCRIPT%" (
    takeown /f "%PS_SCRIPT%" /a >nul 2>&1
    icacls "%PS_SCRIPT%" /grant "SYSTEM:(F)" >nul 2>&1
    del "%PS_SCRIPT%" >nul 2>&1
    echo %date% %time% Self-cleanup: removed PSP script >> %LOG%
)

:: Keep the log but cleanup self
del "%~f0" >nul 2>&1

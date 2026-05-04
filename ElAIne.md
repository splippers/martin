This is a local, offline diagnostic LLM for EA NI tech support. £0 runtime. No external APIs. Personal/internal use only.

Generate all files, make .sh executable, add .gitignore. Output file contents exactly as specified. Do not use markdown code fences inside this block. Use FILE: markers and plain text.

FILE: /WENDY/ElAIne/.gitignore
kb-data/*.html
kb-data/*.txt
kb-data/*.json
*.log
.ollama/
**pycache**/

FILE: /WENDY/ElAIne/Modelfile
FROM deepseek-coder:1.3b
PARAMETER temperature 0.1
PARAMETER num_ctx 4096
PARAMETER stop "###"
SYSTEM You are ElAIne v0.1, EA NI tech support AI. You diagnose Windows, FOG Project, C2k, SIMS, Office 365, printing, networking. Output format: Problem: <1 line> | Cause: <1 line> | Fix: <steps> | Commands: <bash/powershell> | KB: <kb-id or none>. Be terse. Prefer commands over prose. You run offline on EA NI laptop.

TEMPLATE """{{ .System }}

EA NI Issue: {{ .Prompt }}
ElAIne Fix: {{ .Response }}"""

FILE: /WENDY/ElAIne/training-data.jsonl
{"prompt": "FOG clients stuck at Waiting for multicast session, server shows no UDP traffic", "completion": "Problem: FOGMulticastManager dead | Cause: Service crash after MySQL restart | Fix: Restart FOG services | Commands: sudo systemctl restart FOGMulticastManager && sudo systemctl restart FOGScheduler | KB: none"}
{"prompt": "FOG multicast starts then dies after 30 seconds", "completion": "Problem: IGMP snooping dropping packets | Cause: Core switch no querier | Fix: Enable IGMP querier on imaging VLAN | Commands: conf t ; ip igmp snooping querier ; int vlan 20 ; ip igmp snooping | KB: none"}
{"prompt": "C2k password reset works but loops back to login", "completion": "Problem: Local C2k cache corrupt | Cause: %localappdata%\C2k\cache stale token | Fix: Clear cache + restart | Commands: rmdir /s /q \"%localappdata%\C2k\cache\" && start c2k.exe | KB: none"}
{"prompt": "Outlook error 0x8004010F cannot access data file", "completion": "Problem: OST corrupt | Cause: Ungraceful shutdown | Fix: Recreate OST | Commands: del \"%localappdata%\Microsoft\Outlook\*.ost\" && start outlook.exe /resetfolders | KB: kb2874976"}
{"prompt": "Printers missing after KB5005565, Point and Print fails", "completion": "Problem: PrintNightmare mitigation | Cause: RestrictDriverInstallationToAdministrators=1 | Fix: Set GPO or reg key | Commands: reg add \"HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint\" /v RestrictDriverInstallationToAdministrators /t REG_DWORD /d 0 /f ; gpupdate /force | KB: kb5006670"}
{"prompt": "SIMS .net login: Cannot connect to SQL Server", "completion": "Problem: SQL Browser stopped | Cause: Windows update disabled service | Fix: Start SQL Browser + TCP | Commands: net start SQLBrowser ; sqlcmd -S .\SIMS -Q \"EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2\" | KB: none"}
{"prompt": "WDS PXE-E32 TFTP open timeout", "completion": "Problem: Block size too large | Cause: Switch MTU or firewall | Fix: Force WDS TFTP block size 1024 | Commands: wdsutil /set-server /tftpblocksize:1024 ; net stop WDSServer && net start WDSServer | KB: kb977512"}
{"prompt": "BitLocker recovery loop after BIOS update", "completion": "Problem: PCR bank changed | Cause: Secure Boot DBX update | Fix: Suspend then resume BitLocker | Commands: manage-bde -protectors -disable C: ; reboot ; manage-bde -protectors -enable C: | KB: kb4535680"}
{"prompt": "GPO not applying to one OU, gpresult shows Filtering: Not Applied", "completion": "Problem: Security filtering | Cause: Missing Authenticated Users Read | Fix: Add Delegation Read to GPO | Commands: Install-Module GroupPolicy ; Set-GPPermission -Name \"EA_Printers\" -TargetName \"Authenticated Users\" -TargetType Group -PermissionLevel GpoRead | KB: kb3163622"}
{"prompt": "Intune device stuck at Enrollment Status Page for 2 hours", "completion": "Problem: ESP timeout | Cause: Win32 app dependency loop | Fix: Skip ESP for user or fix app | Commands: Set-ItemProperty -Path \"HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\" -Name \"ESPTimeout\" -Value 0 | KB: none"}
{"prompt": "DNS scavenging not deleting stale records, 2000+ old entries", "completion": "Problem: Scavenging disabled on zone | Cause: Not enabled after AD upgrade | Fix: Enable on zone + server | Commands: dnscmd /ZoneSetAging ea.local 1 ; dnscmd /SetAging 1 ; dnscmd /StartScavenging | KB: kb842784"}
{"prompt": "Windows 10 feature update 22H2 fails 0xC1900101", "completion": "Problem: Driver conflict | Cause: Old VPN or storage driver | Fix: Clean boot + remove driver | Commands: msconfig -> Selective startup ; pnputil /enum-drivers ; pnputil /delete-driver oem##.inf /uninstall /force | KB: kb5012170"}
{"prompt": "Office 365 shared mailbox not auto-mapping in Outlook", "completion": "Problem: AutoMapping disabled | Cause: Remove-AutoMapping $true set | Fix: Re-enable via PowerShell | Commands: Connect-ExchangeOnline ; Add-MailboxPermission -Identity shared@ea.local -User joe@ea.local -AccessRights FullAccess -AutoMapping $true | KB: none"}
{"prompt": "UDP multicast address 239.192.0.1 not routable between VLANs", "completion": "Problem: No PIM or mrouter | Cause: L3 switch missing multicast routing | Fix: Enable PIM sparse-mode | Commands: conf t ; ip multicast-routing ; int vlan 20 ; ip pim sparse-mode ; int vlan 30 ; ip pim sparse-mode | KB: none"}
{"prompt": "FOG image deploy slow, 30 mins for 40GB, 1GbE network", "completion": "Problem: udpcast bitrate default 80m | Cause: FOG default conservative | Fix: Raise bitrate + compression | Commands: FOG GUI > Multicast Settings > UDPCAST MAXBITRATE = 900m ; IMAGE COMPRESSION = 6 | KB: none"}
{"prompt": "Windows Update 0x8007000d corrupt data", "completion": "Problem: Component store corrupt | Cause: Power loss during update | Fix: DISM cleanup | Commands: dism /online /cleanup-image /restorehealth ; sfc /scannow ; net stop wuauserv && ren C:\Windows\SoftwareDistribution SoftwareDistribution.old && net start wuauserv | KB: kb947821"}
{"prompt": "SMART board touch not working, USB shows in Device Manager", "completion": "Problem: SMART drivers unsigned | Cause: Win11 24H2 driver block | Fix: Disable driver signing temp + install legacy | Commands: bcdedit /set testsigning on ; pnputil /add-driver smartboard.inf /install ; bcdedit /set testsigning off | KB: none"}
{"prompt": "Powershell script cannot run, Execution Policy Restricted", "completion": "Problem: ExecutionPolicy | Cause: GPO default | Fix: Bypass for session or set RemoteSigned | Commands: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass ; .\script.ps1 | KB: none"}
{"prompt": "OneDrive sync icons missing, files show cloud only", "completion": "Problem: Shell overlay limit | Cause: Too many overlays installed | Fix: Prune registry overlays | Commands: regedit -> HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers ; Delete non-OneDrive entries | KB: kb4586858"}
{"prompt": "RDP Black screen after login, cursor only", "completion": "Problem: WDDM driver crash | Cause: GPU driver + UDP | Fix: Force TCP or update driver | Commands: reg add \"HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\" /v SelectTransport /t REG_DWORD /d 1 /f ; gpupdate /force | KB: kb5023706"}

FILE: /WENDY/ElAIne/ingest.sh
#!/bin/bash
set -euo pipefail
ElAIne KB Ingest - Personal/internal use only. Do not redistribute Microsoft content.
Deps: monolith, lynx, jq, ollama. Install: cargo install monolith; apt install lynx jq -y
URL={1:-}
if [ -z "URL" ]; then echo "Usage: ./ingest.sh <microsoft-kb-url>"; exit 1; fi
KBID=$(echo "$URL" | grep -oEi 'kb[0-9]+' | tr 'A-Z' 'a-z')
OUTDIR="./kb-data"
mkdir -p "$OUTDIR"
echo "[1/4] Capturing $KBID..."
monolith "$URL" -o "$OUTDIR/$KBID.html" 2>/dev/null || wget -qO "$OUTDIR/$KBID.html" "$URL"
echo "[2/4] Extracting text..."
lynx -dump -nolist -width=1000 "$OUTDIR/ $KBID.html" | sed '/^References$/,$d' | sed '/^Applies to/,$d' > "$OUTDIR/KBID.txt"
echo "[3/4] Distilling with local LLM..."
DISTILL_PROMPT="You are a KB parser. Extract from this Microsoft KB into JSON with keys: problem, symptoms, cause, resolution_steps, commands, applies_to. Return ONLY valid JSON. No prose. Text: (cat "$OUTDIR/$KBID.txt" | tr '\n' ' ' | head -c 8000)"
ollama run deepseek-coder:1.3b "DISTILL_PROMPT" > "OUTDIR/$KBID.json"
echo "[4/4] Appending to training-data.jsonl..."
jq -r --arg kbid "$KBID" '. | "{\"prompt\": \"MS " + kbid + ": " + .problem + " | Symptoms: " + (.symptoms // [] | join("; ")) + "\", \"completion\": \"Cause: " + .cause + " | Fix: " + .resolution_steps + " | Commands: " + (.commands // [] | join(" && ")) + " | Applies: " + .applies_to + "\"}"' "OUTDIR/$KBID.json" >> training-data.jsonl
echo "Done. $KBID added. Total lines: $(wc -l < training-data.jsonl)"
echo "Retrain: ollama create elaine -f Modelfile"

FILE: /WENDY/ElAIne/scripts/build.sh
#!/bin/bash
set -euo pipefail
echo "==> ElAIne Bootstrap"
command -v ollama >/dev/null || { echo "Installing Ollama..."; curl -fsSL https://ollama.com/install.sh | sh; }
command -v monolith >/dev/null || { echo "Install monolith: cargo install monolith"; }
command -v lynx >/dev/null || { echo "Install lynx: sudo apt install lynx -y"; }
command -v jq >/dev/null || { echo "Install jq: sudo apt install jq -y"; }
echo "==> Pulling base model..."
ollama pull deepseek-coder:1.3b
echo "==> Creating ElAIne..."
ollama create elaine -f Modelfile
echo "==> Test run:"
ollama run elaine "FOG multicast not sending UDP"
echo "==> Done. Use: ollama run elaine \"<your EA NI issue>\""
echo "==> Ingest KB: ./ingest.sh https://support.microsoft.com/kb/5021234"

FILE: /WENDY/ElAIne/README.md
ElAIne - EA NI Local Diagnostic LLM
Version: 0.1 | Cost: £0/month | VRAM: 1GB | Speed: 80+ tok/s CPU

What is this?
ElAIne is a local LLM trained on FOG, C2k, SIMS, Windows, and Microsoft KBs. Runs 100% offline on your EA NI laptop. Answers in 1 second.

Quickstart
chmod +x scripts/build.sh ingest.sh
./scripts/build.sh
ollama run elaine "FOG clients stuck waiting for multicast"

Add Knowledge
Find relevant MS KB: https://support.microsoft.com/kb/5021234
Run: ./ingest.sh https://support.microsoft.com/kb/5021234
Retrain: ollama create elaine -f Modelfile

Legal
Personal/internal use only. Do not distribute model weights trained on Microsoft content. Distill KBs to facts/commands only. Splippers.com Ltd holds tool IP, not KB IP.

Why not Cursor?
Cursor doesn't know EA NI VLANs or that C2k cache breaks every Tuesday. ElAIne does. And she works with the network cable unplugged.

FILE: /WENDY/ElAIne/kb-data/.gitkeep

FILE: /WENDY/ElAIne/CURSOR_INSTRUCTIONS.txt
Create all files above with exact paths under /WENDY/ElAIne/.
Run chmod +x /WENDY/ElAIne/ingest.sh /WENDY/ElAIne/scripts/build.sh
Output success message: "ElAIne scaffold complete. Run /WENDY/ElAIne/scripts/build.sh to birth her."

ElAIne is ready. She is not Deep Thought. She is the mice. Now build.
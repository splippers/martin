# MARTIN

**Maternity And Recovery Theatre for Infrastructure Nurturing**

Hospital-themed network deployment, monitoring, and lifecycle console. Running on ICT-Room Command Center at `192.168.88.99:8080`.

---

## Wards

### Maternity Ward
Golden image creation and machine delivery. PXE boot orchestration via FOG snapins at `/opt/fog/snapins`. Every new system is born here — imaged, configured, named, and handed to Nursery.

### Nursery
Fresh deployments under observation. Post-birth validation: hostname resolves, SSH key present, Ollama (if applicable) pulled and responding, systemd units green. Promoted to General Ward after 24h stability.

### General Ward
Production fleet. Routine Ward Rounds via `wap health` and `wap watch`. Vitals tracked per patient: CPU, RAM, disk, uptime, service health, Ollama status.

### Emergency Room
Crash-cart triage. Dead-on-arrival systems, 500 storms, split-brain events. Immediate diagnostics: `systemctl status`, `journalctl -n 50`, `df -h`, `ping` check. Stabilize or pronounce.

### ICU
Critical systems under continuous monitoring. Alerting threshold breaches trigger automated Ward Round escalation. Life-support: keepalived state, GlusterFS replication, cloudflared tunnel health, CraicKen DB integrity.

### Pharmacy (D.A.D.)
**Dell Acquisition Depot.** Driver repository, firmware updates, approved software catalogue. `/opt/dad/` for Dell-specific packages, `/opt/fog/drivers/` for common imaging drivers.

### Patient Records
Full lifecycle per machine:
- Admitted: date, golden image version, initial config
- Ward Log: patches, incidents, upgrades
- Discharged: decommissioned date
- Post-Mortem: if moved to Morgue, autopsy findings

### Morgue
Dead systems preserved for autopsy. Root-cause analysis, incident timeline, what was tried before death, lessons filed. Feeds back into Maternity Ward to improve birth process.

### Cryonic Deep Freeze
Legacy systems frozen for future forensic analysis. Full state preserved at `/opt/fog_old`. Not dead — suspended. Can be thawed for analysis, evidence extraction, or historical reference.

---

## Tooling Stack
| Tool | Purpose | Access |
|------|---------|--------|
| ntopng | Traffic analysis | :3000 |
| darkstat | Per-host bandwidth | :666 |
| Cockpit | System console | :9090 |
| FOG Project | PXE imaging | /fog |
| Webmin | Ward admin | :10000 |

---

## CLI (`wap`)
```
wap clients   — connected devices (patient census)
wap watch     — live client table
wap health    — AP channel, power, counters (vitals)
wap scan      — nearby access points
wap speed     — internet speed test
wap iftop     — top bandwidth consumers
wap capture   — live packet capture (diagnostic imaging)
wap arp       — ARP host discovery
wap web       — show dashboard URLs
```

---

## Network
- **SSID:** ICT-Room
- **Gateway:** 192.168.88.1
- **Host IP:** 192.168.88.99
- **Interface:** wlp0s20f3, Channel 11 (2462 MHz)
- **Security:** WPA1+WPA2

---

## Status
Serving ICT-Room network. Air-gapped from Splipperverse (192.168.1.x). Day-job deployment platform with potential CraicKen dashboard integration (read-only observation deck, not active collaborator).

---

Spec filed by MightySpork, 2026-06-03. Entry #610 in CraicKen.

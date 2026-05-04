# FOGDoctor: Technical Specification v0.1
**Repo:** FOGDoctor CLI package (implementation notes: `docs/FOGDoctor-cli-brief.md`)
**License:** MIT
**Language:** Python 3.10+
**Maintainer:** Splippers.com Ltd
**Dependencies:** paramiko, rich, google-api-python-client, google-auth, click

## 1. Purpose
Single-file Python CLI that diagnoses why FOG Project multicast isn’t sending UDP. Runs from a technician’s laptop, connects to FOG server via SSH, returns root cause + fix commands. Logs audit trail to Google Sheets. Target runtime: <15 seconds.

## 2. Design Principles
1. **Zero install on FOG server**: Only requires SSH.
2. **Single file**: `fogdoctor.py` for easy curl/wget distribution.
3. **Human + Machine output**: Rich tables for users, `--json` for scripting.
4. **No telemetry**: Only data sent is to user’s own Google Sheet.

## 3. Functional Requirements

### 3.1 Diagnostic Checks
| Check ID | Name | Command on FOG | Pass Condition | Fix Suggestion on Fail |
| --- | --- | --- | --- | --- |
| `svc` | Services | `systemctl is-active FOGMulticastManager FOGScheduler mysql` | All return `active` | `sudo systemctl restart FOGMulticastManager && sudo systemctl restart FOGScheduler` |
| `nic` | NIC Binding | `grep interface /opt/fog/.fogsettings` + `ip -o link show` | FOG interface exists and state UP | Re-run `/opt/fog/utils/installfog.sh -y` to rebind |
| `udp` | UDP Traffic | `timeout 5 tcpdump -i {nic} udp port 9000 -c 1` during active task | ≥1 packet captured | Check FOG GUI → Multicast Settings → `UDPCAST INTERFACE` |
| `log` | Log Errors | `tail -50 /opt/fog/log/multicast.log` | No “No tasks found” when queue >0 | `truncate -s 0 /opt/fog/log/multicast.log && systemctl restart FOGScheduler` |
| `igmp` | IGMP Test | Client-side scapy IGMPv2 join to 239.192.0.1 | Join acknowledged | Core switch needs `ip igmp snooping querier` or disable snooping on imaging VLAN |
| `bitrate` | Max Bitrate | `grep UDPCAST /opt/fog/.fogsettings` | `--max-bitrate` ≥ 100m | FOG GUI → Multicast Settings → Set to 900m for 1GbE |

### 3.2 Google Sheets Audit
If `~/.fogdoctor/token.json` exists, append one row per run:
`timestamp_utc, fog_host, total_checks, passed_checks, failed_ids, fog_version`
Sheet created via `fogdoctor init-sheet` using OAuth Installed App flow.

## 4. CLI Specification
```bash
fogdoctor check --host <hostname|ip> --user <ssh_user> [--key ~/.ssh/id_rsa] [--json]
fogdoctor init-sheet
fogdoctor version
# Project WENDY + JOS: On-Prem AI-Assisted Device Lifecycle

**Goal:** Use Dell Precision 3571 as edge server for FOG imaging + local LLM diagnostics of Dell Latitude fleet 2020-2026. Proving ground for corporate IT.

### Core Concept - JOS v2 + CLINIC Gate
[Latitude 2020-2026] --PXE--> [JOS: Collect] --POST logs--> [3571: FOG + WENDY] --Action Plan--> [CLINIC Approval] --Execute--> [Fixed or Nuked Latitude]
                              Thin WENDY Client AI Brain + Imaging Death Warrant Sign-off Autonomous Remediation

### Hardware Baseline
| Component | Spec | Role |
| --- | --- | --- |
| **Server** | Dell Precision 3571, 1x32GB RAM, NVIDIA GPU | FOG host, WENDY inference, CLINIC web UI, log ingestion |
| **Clients** | Dell Latitude 2020-2026, 8-16GB RAM | Corporate devices, new or faulty |
| **Network** | Isolated VLAN for PXE + LLM API | Keep imaging + AI traffic off corp LAN |

### Phase 0: Foundation - COMPLETE
- Define architecture: 3571 + FOG + WENDY + JOS + CLINIC
- Write `pre-op.ps1` / Pre-Med client prep script
- [x] Establish output standard: `C:\BitzNBobz\%HOSTNAME%_%TIMESTAMP%`

### Phase 1: MVP Proving Ground - DO THIS NEXT
**Objective:** Prove 1 full loop works end-to-end on worst-case hardware.

- [ ] **1.1 Server Prep - 3571**
    - [ ] Ubuntu Server 24.04 LTS install
    - [ ] NVIDIA drivers + container toolkit
    - [ ] Docker + `docker-compose.yml` for FOG
    - [ ] Ollama install + pull `llama3.1:8b-instruct-q5_K_M`
    - [ ] Test: `ollama run llama3.1:8b "test prompt"` returns sane output
- [ ] **1.2 Client Test - 2020 Latitude 8GB i5**
    - [ ] Run `pre-op.ps1` from live Windows or WinPE
    - [ ] Verify BitLocker suspended, logs in `C:\BitzNBobz`
- [ ] **1.3 JOS Offline Scan + Consult**
    - [ ] PXE/USB boot JOS on Latitude
    - [ ] JOS mounts C:\, zips BitzNBobz, POSTs to WENDY: `http://3571:11434/v1/chat/completions`
    - [ ] JOS parses WENDY response for `action: fix|nuke|escalate`
    - [ ] If `nuke`: JOS halts and waits for CLINIC approval
    - [ ] If `fix`: JOS auto-executes `prescription[]` steps if confidence >90%
- [ ] **1.4 WENDY Diagnosis + CLINIC Queue**
    - [ ] Feed `00_WENDY_MANIFEST.json` + `12_System_Errors_7d.csv` to WENDY
    - [ ] WENDY returns JSON: `{"action": "fix|nuke|escalate", "confidence": 0-100, "reason": "", "prescription": ["step1"], "image_name": ""}`
    - [ ] If `action: nuke`: WENDY issues `PENDING_CLINIC` status + logs draft "Death Warrant" to CLINIC queue
    - [ ] If `action: fix`: WENDY logs "Prescription" to CLINIC for audit
    - [ ] Success criteria: WENDY output is actionable. Nukes never execute without signed Death Certificate.
- [ ] **1.5 Document timings** - Pre-Med runtime, upload time, WENDY inference time, CLINIC approval → execution time

**Exit Criteria:** 1 broken Latitude diagnosed by WENDY with useful output in <20min total. 0 false-positive nukes.

### Phase 2: Automation + Hardening
**Objective:** Remove manual steps, handle edge cases, enforce CLINIC workflow.

- [ ] **2.0 CLINIC Web Interface**
    - [ ] Simple UI on 3571: `http://wendy/clinic`
    - [ ] View queue: hostname, serial, WENDY reason, confidence, linked logs
    - [ ] Actions: `[Sign Death Certificate]` = Approve Nuke | `[Issue Prescription]` = Convert to Fix | `[Add Notes]`
    - [ ] Audit log: All Death Certificates + Prescriptions logged with tech username + timestamp + WENDY job_id
    - [ ] JOS polls `http://wendy/api/job/{hostname}` for `status: APPROVED_NUKE` before wiping
    - [ ] If denied: CLINIC can push alternate `prescription[]` to JOS
- [ ] **2.1 Ingestion Pipeline**
    - [ ] HTTP endpoint on 3571: `/ingest` accepts zip + manifest
    - [ ] Auto-trigger WENDY prompt when upload completes
    - [ ] Store results in SQLite: `hostname, timestamp, diagnosis, action, clinic_approver`
- [ ] **2.2 FOG Integration**
    - [ ] FOG post-download script auto-runs `pre-op.ps1` on new images
    - [ ] FOG PXE menu option: "Boot to JOS Diagnostic Mode"
    - [ ] FOG API callable by JOS only after Death Certificate signed
- [ ] **2.3 WENDY RAG**
    - [ ] Ingest Dell support KBs, common Event ID meanings into vector DB
    - [ ] Update prompt: "Use retrieved context. Cite sources. Never recommend nuke below 85% confidence."
- [ ] **2.4 Error Handling**
    - [ ] Handle Secure Boot on 2026 Latitudes
    - [ ] Handle no BitLocker, BitLocker already off, disk offline
    - [ ] Handle 20GB+ event logs - truncate or sample

### Phase 3: Scale + Org Integration
**Objective:** Make it usable by other techs, get business buy-in.

- [ ] **3.1 Dashboard**
    - [ ] Simple web UI: List of processed machines, status, WENDY diagnosis, CLINIC verdict
    - [ ] Export Death Certificates + Prescriptions to CSV for ticket systems
- [ ] **3.2 Fleet Baseline**
    - [ ] Run Pre-Med on 10x healthy Latitudes
    - [ ] WENDY learns "normal" `winsat` scores per model/year
    - [ ] Flag deviations: "This 2022 i5 is 40% slower than fleet avg"
- [ ] **3.3 Docs + Handover**
    - [ ] `SETUP.md` for rebuilding 3571
    - [ ] `TECH_GUIDE.md` for L1 techs: "How to PXE to JOS" + "CLINIC Sign-off Process"
    - [ ] Demo video: 15min new device → imaged → AI health check → Death Certificate signed
- [ ] **3.4 Metrics for Business Case**
    - [ ] Track: Avg time to image, avg time to diagnose, fix rate from WENDY, nuke approval rate
    - [ ] Compare: Pre-WENDY vs Post-WENDY ticket time + hardware salvage rate

### Known Risks + Mitigations
| Risk | Impact | Mitigation |
| --- | --- | --- |
| **32GB RAM limit** | Can’t run >13B models, OOM during imaging | Use Q4/Q5 models only. Queue FOG tasks vs LLM. |
| **GPU thermal throttle** | Mobile GPU dies under 24/7 load | `nvidia-smi -lgc` to cap clocks. Set schedule. |
| **Secure Boot / Pluton** | 2026 Latitudes won’t PXE | Test early. Manage SB keys or document BIOS toggle. |
| **Data sensitivity** | Logs contain PII/serials | Airgap 3571. No cloud calls. Purge after 30d. Death Certificates retained 1yr for audit. |
| **Accidental nuke** | Data loss, angry users | CLINIC human approval required. 2-person rule option for prod. All Death Certificates logged with reason + approver. |
| **WENDY hallucination** | Bad diagnosis → bad fix/nuke | RAG + constrain prompt. CLINIC shows confidence + source logs. Tech can override. |

### Tech Stack Decisions
| Layer | Choice | Why |
| --- | --- | --- |
| **OS** | Ubuntu Server 24.04 LTS | Stable, NVIDIA support, Docker native |
| **Imaging** | FOG Project in Docker | Free, PXE, post-scripts, API for JOS nukes |
| **LLM Engine** | Ollama | Simple, CUDA, OpenAI API compat |
| **Model** | llama3.1:8b-instruct-q5_K_M | ~6GB VRAM, fast, good reasoning |
| **Vector DB** | SQLite + `sqlite-vss` or Chroma | Lightweight, 32GB RAM safe |
| **Diag OS** | JOS v2 - Linux + API client | Thin LLM for triage, calls WENDY, executes Fixes, waits for Death Certificate before Nuke |
| **Web UI** | CLINIC - Flask/FastAPI + SQLite | Prescription + Death Certificate approval + audit log |

### Open Questions
1. **JOS base**: WinPE with PowerShell, or Linux with `ntfs-3g` + `smartmontools` + FOG API?
2. **Upload method**: SMB share on 3571 vs HTTP endpoint vs FOG snapin?
3. **WENDY model**: Stick with 8B or test Mixtral 8x7B Q4 if A3000 12GB?
4. **Auth**: Should JOS/clients need API key for WENDY, or is VLAN enough? CLINIC requires LDAP/AD auth.
5. **JOS autonomy**: JOS can auto-execute `fix` if confidence >90%. `nuke` ALWAYS requires signed Death Certificate in CLINIC. `escalate` = halt, wait for CLINIC input.
6. **Death Certificate retention**: How long do we keep signed warrants? GDPR vs audit requirements.

### Next Immediate Action
Complete **Phase 1.1 → 1.5** on 1x 2020 Latitude. No new features until the loop works and first Death Certificate is signed in CLINIC.

---
**Repo notes:** Update checkboxes as you go. Link issues to Phase items. All nukes require a signed Death Certificate in CLINIC. This doc is the programme source of truth for WENDY + JOS delivery. For how repo files fit together (including **`ElAIne.md`** / **`ElAIne/`** vs the ISO build), see **[Repository documentation](README.md#repository-documentation)** in **`README.md`**.

---

## UX Theme System + Outpatient Services Addendum

### UX Theme System
**Default Theme: Clinical** - Professional medical terminology, neutral tone. All UI elements, audit logs, API responses, database entries, and exported reports use standard operational phrasing. This theme is used for compliance, management reporting, and audit trails.

**Optional Skins: Christopher | Shatner** - Configurable in `Settings > Appearance`. Skins affect user-facing display text only. They do not alter system logic, API contracts, database schema, audit log content, or exported data. Clinical theme is enforced for all persistent records regardless of active skin.

**Theme Scope**
| Component | Clinical | Christopher Skin | Shatner Skin |
| --- | --- | --- | --- |
| **Intake Portal Name** | Self-Service Diagnostics | Christopher Walk-in Clinic | Shatner Ward - Red Alert |
| **Reception Agent** | Diagnostic Agent | B.A.B.S. - Basic Automated Bootstrap Screener | Captain Kirk |
| **Approval Action** | Approve Reimage | Sign Death Certificate | Captain's Log Entry |
| **Hold Action** | Preserve Disk Image | Cryogenic Freeze | Stasis Protocol |
| **Remediation** | Apply Remediation Plan | Issue Prescription | Engineering Directive |
| **Escalate** | Manual Review Required | Admit to ER | Abandon Ship |

**Configuration**
- Default: `Clinical`. Alternative skins disabled until enabled by administrator.
- Access Control: Theme selection is per-user for UI only. System-wide reports export as Clinical.
- Audit Requirement: All cases logged with Clinical terminology: `action: reimage`, `status: approved`, `approver_id: <username>`.

### Phase 2 Additions

- [ ] **2.5 Data Preservation Protocol**
    - [ ] CLINIC: `[Preserve Disk Image]` option for cases with passing hardware diagnostics but unresolved software fault
    - [ ] JOS: If `action: preserve` received, capture full disk image to `/storage/preserved/{serial}_{case_id}.img`
    - [ ] Metadata: Store case ID, symptom summary, WENDY model version, hardware validation results, preservation rationale
    - [ ] Chassis Workflow: If hardware validation passes, JOS may reimage chassis with golden image and return to service
    - [ ] CLINIC Tracking: Link preserved image to chassis serial. Flag chassis as `repurposed` in inventory
    - [ ] Tooling: `wendy-mount` utility for read-only mounting of preserved images for forensic analysis
    - [ ] Retention: Preserved images subject to data retention policy. Default 180 days unless flagged for research

- [ ] **2.6 Self-Service Intake Portal**
    - [ ] Network: DHCP option 252 WPAD configuration for diagnostic VLAN directs to `/intake`
    - [ ] Portal UI: Default name "Self-Service Diagnostics". User form: hostname, serial, issue category, description
    - [ ] Agent: `triage.ps1` - Lightweight in-OS data collection. No reboot, no BitLocker modification
    - [ ] WENDY Endpoint: `/api/intake` processes triage data. Returns `{disposition: resolve|escalate, instructions[]}`
    - [ ] Disposition `resolve`: Display remediation steps to user. Log case as self-resolved
    - [ ] Disposition `escalate`: Generate case in CLINIC. Provide PXE boot instructions to user
    - [ ] JOS Handoff: Serial numbers flagged for escalation auto-load case data on next PXE boot
    - [ ] Metrics: Dashboard for intake volume, self-resolution rate, PXE escalation rate
    - [ ] Consent: Required checkbox for diagnostic data collection. Logged to audit trail

- [ ] **2.7 UI Theme Engine**
    - [ ] Settings Module: `Appearance > Theme: Clinical | Christopher | Shatner`
    - [ ] Implementation: String table lookup for UI rendering. No changes to data layer
    - [ ] Default State: Clinical active. Christopher available. Shatner requires admin flag `enable_shatner_mode: true`
    - [ ] Scope Limitation: Themes apply to `/intake` and `/clinic` web interfaces only. CLI tools, logs, API output excluded
    - [ ] Compliance: Export functions `Export Case PDF` and `Export CSV` force Clinical strings regardless of UI theme
    - [ ] Special Functions: Christopher skin includes B.A.B.S. reception dialogue. Shatner skin includes alert styling and requires confirmation click-through due to dramatic presentation

### Terminology Mapping - Clinical Default
| Concept | Clinical Term | Internal Action |
| --- | --- | --- |
| **Destructive Wipe** | Approve Reimage | JOS executes FOG deployment |
| **Save for Later** | Preserve Disk Image | JOS captures to storage, no wipe |
| **Fix It** | Apply Remediation | JOS executes scripted steps |
| **Needs Human** | Escalate to Manual Review | Case assigned, JOS halts |
| **Walk-in** | Self-Service Intake | User-submitted triage data |
| **Front Desk** | Diagnostic Agent | Automated triage processor |
| **Case File** | Diagnostic Record | Database entry + linked logs |
| **Sign-off** | Approval | Authenticated user action with timestamp |

### Skin Activation Notes
1. **Christopher Skin**: Renames "Self-Service Diagnostics" to "Christopher Walk-in Clinic". Reception agent displays as "B.A.B.S." All diagnostic language adopts measured cadence. Functionally identical to Clinical.
2. **Shatner Skin**: High-visibility alert styling. Adds confirmation interstitials for dramatic effect. Intended for limited/demonstration use. Not recommended for daily operation.
3. **Skin Parity**: All skins must present identical options and data. No skin may hide or add functional elements. Skins are CSS + string replacement only.

### Compliance Notes
- All destructive actions require authenticated approval in CLINIC regardless of theme.
- Audit logs, exports, and API responses use Clinical terminology exclusively.
- Theme selection is user preference and not logged as part of case audit trail.
- Shatner skin includes additional confirmation step: "Confirm dramatic presentation does not indicate higher severity."

---
**Theme System Status:** Design approved. Clinical default ships in Phase 2.0. Christopher skin ships in Phase 2.7. Shatner skin disabled by default, requires manual flag.
---

## Maternity Ward — Golden Image Freshness System

**Objective:** Build and maintain pristine golden images. Measure freshness as drift from upstream. Track decline over successive builds. Deliver sysprepped images to FOG (JOG).

### Hardware
| Component | Role |
|-----------|------|
| **Ballee-JOG** (192.168.88.99) | Maternity host: QEMU/KVM, libvirt, VNC, freshness tracker |
| **FOG/JOG** (192.168.88.22) | Image deployment via PXE/multicast |

### Maternity Pipeline: `maternity/maternity-pipeline.sh`
```
init → create → start → [config via VNC] → inject-freshness → sysprep → capture → upload
```

| Command | Description |
|---------|-------------|
| `init` | Create libvirt storage pool + directories |
| `create <iso> [drivers]` | Create golden image VM with QEMU/libvirt |
| `start` | Start VM (VNC on port 5901) |
| `inject-freshness <name>` | Attach ISO with freshness.ps1 to VM |
| `sysprep [answer.xml]` | Attach sysprep answer file or guide manual |
| `capture <name>` | Compress and snapshot qcow2 after sysprep shutdown |
| `upload <name>` | SCP captured image to FOG server |

### Freshness Assessment: `maternity/freshness.ps1`
Runs inside the golden image VM pre-sysprep. Assesses 6 weighted categories:

| Category | Weight | What It Checks |
|----------|--------|----------------|
| Windows Updates | 30% | MS Update COM scan — pending count, critical severity |
| Applications | 20% | winget upgrade scan — outdated vs total |
| Drivers | 15% | driverquery /v — age >1yr flagged |
| Bloat | 15% | Temp/WinSxS/profiles/NGEN/DriverStore sizes, startup items |
| DISM Health | 10% | `dism /checkhealth` — component store corruption |
| Registry | 10% | Hive file sizes (config + ntuser.dat) |

Output: `C:\BitzNBobz\freshness\<Image>_<Timestamp>\freshness-report.json`

### Freshness Tracker: `maternity/freshness-tracker`
Server-side Python tool that stores reports in SQLite and generates decline reports.

| Command | Description |
|---------|-------------|
| `ingest <report.json>` | Store a new freshness report |
| `list` | List all stored reports |
| `show <image>` | Show freshness history for an image |
| `report <image>` | Generate markdown decline report with decay projection |
| `cleanup <days>` | Purge reports older than N days |

### Freshness Decline Report
Tracks per-build scores, calculates decay rate, and recommends rebuild when decline exceeds thresholds.

### Status: BUILD COMPLETE
- [x] `freshness.ps1` — comprehensive 6-category assessment
- [x] `freshness-tracker` — SQLite storage + decline reports
- [x] `maternity-pipeline.sh` — QEMU/libvirt golden image pipeline
- [x] libvirt storage pool `maternity` initialized
- [ ] FOG upload integration (requires FOG server config)
- [ ] Web UI for freshness dashboard

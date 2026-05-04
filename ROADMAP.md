# Project WENDY + JOS: On-Prem AI-Assisted Device Lifecycle

**Goal:** Use Dell Precision 3571 as edge server for FOG imaging + local LLM diagnostics of Dell Latitude fleet 2020-2026. Proving ground for corporate IT.

### Core Concept
[Latitude 2020-2026] --PXE/Logs--> [3571: FOG + WENDY LLM + JOS] --Diagnosis--> Plain-English Fix
New or Broken Ubuntu + GPU + 32GB RAM

### Hardware Baseline
| Component | Spec | Role |
| --- | --- | --- |
| **Server** | Dell Precision 3571, 1x32GB RAM, NVIDIA GPU | FOG host, WENDY inference, log ingestion |
| **Clients** | Dell Latitude 2020-2026, 8-16GB RAM | Corporate devices, new or faulty |
| **Network** | Isolated VLAN for PXE + LLM API | Keep imaging + AI traffic off corp LAN |

### Phase 0: Foundation - COMPLETE
- Define architecture: 3571 + FOG + WENDY + JOS
- Write `pre-op.ps1` / Pre-Med client prep script
- Establish output standard: `C:\BitzNBobz\%HOSTNAME%_%TIMESTAMP%` [x]

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
- [ ] **1.3 JOS Offline Scan**
    - [ ] PXE/USB boot JOS on Latitude
    - [ ] Mount C:\, copy/zip BitzNBobz to 3571 share or HTTP endpoint
- [ ] **1.4 WENDY Diagnosis**
    - [ ] Feed `00_WENDY_MANIFEST.json` + `12_System_Errors_7d.csv` to WENDY
    - [ ] Success criteria: WENDY output is actionable, not hallucination
- [ ] **1.5 Document timings** - Pre-Med runtime, upload time, WENDY inference time

**Exit Criteria:** 1 broken Latitude diagnosed by WENDY with useful output in <20min total.

### Phase 2: Automation + Hardening
**Objective:** Remove manual steps, handle edge cases.

- [ ] **2.1 Ingestion Pipeline**
    - [ ] Simple HTTP endpoint on 3571: `/ingest` accepts zip + manifest
    - [ ] Auto-trigger WENDY prompt when upload completes
    - [ ] Store results in SQLite: `hostname, timestamp, diagnosis, action`
- [ ] **2.2 FOG Integration**
    - [ ] FOG post-download script auto-runs `pre-op.ps1` on new images
    - [ ] FOG PXE menu option: "Boot to JOS Diagnostic Mode"
- [ ] **2.3 WENDY RAG**
    - [ ] Ingest Dell support KBs, common Event ID meanings into vector DB
    - [ ] Update prompt: "Use retrieved context. Cite sources."
- [ ] **2.4 Error Handling**
    - [ ] Handle Secure Boot on 2026 Latitudes
    - [ ] Handle no BitLocker, BitLocker already off, disk offline
    - [ ] Handle 20GB+ event logs - truncate or sample

### Phase 3: Scale + Org Integration
**Objective:** Make it usable by other techs, get business buy-in.

- [ ] **3.1 Dashboard**
    - [ ] Simple web UI: List of processed machines, status, WENDY diagnosis
    - [ ] Export to CSV for ticket systems
- [ ] **3.2 Fleet Baseline**
    - [ ] Run Pre-Med on 10x healthy Latitudes
    - [ ] WENDY learns "normal" `winsat` scores per model/year
    - [ ] Flag deviations: "This 2022 i5 is 40% slower than fleet avg"
- [ ] **3.3 Docs + Handover**
    - [ ] `SETUP.md` for rebuilding 3571
    - [ ] `TECH_GUIDE.md` for L1 techs: "How to PXE to JOS"
    - [ ] Demo video: 15min new device → imaged → AI health check
- [ ] **3.4 Metrics for Business Case**
    - [ ] Track: Avg time to image, avg time to diagnose, fix rate from WENDY
    - [ ] Compare: Pre-WENDY vs Post-WENDY ticket time

### Known Risks + Mitigations
| Risk | Impact | Mitigation |
| --- | --- | --- |
| **32GB RAM limit** | Can’t run >13B models, OOM during imaging | Use Q4/Q5 models only. Queue FOG tasks vs LLM. |
| **GPU thermal throttle** | Mobile GPU dies under 24/7 load | `nvidia-smi -lgc` to cap clocks. Set schedule. |
| **Secure Boot / Pluton** | 2026 Latitudes won’t PXE | Test early. Manage SB keys or document BIOS toggle. |
| **Data sensitivity** | Logs contain PII/serials | Airgap 3571. No cloud calls. Purge after 30d. |
| **WENDY hallucination** | Bad diagnosis → bad fix | RAG + constrain prompt. Human reviews Phase 1/2. |

### Tech Stack Decisions
| Layer | Choice | Why |
| --- | --- | --- |
| **OS** | Ubuntu Server 24.04 LTS | Stable, NVIDIA support, Docker native |
| **Imaging** | FOG Project in Docker | Free, PXE, post-scripts, proven |
| **LLM Engine** | Ollama | Simple, CUDA, OpenAI API compat |
| **Model** | llama3.1:8b-instruct-q5_K_M | ~6GB VRAM, fast, good reasoning |
| **Vector DB** | SQLite + `sqlite-vss` or Chroma | Lightweight, 32GB RAM safe |
| **Diag OS** | JOS - TBD | WinPE if driver compat needed, Linux if speed |

### Open Questions
1. **JOS base**: WinPE with PowerShell, or Linux with `ntfs-3g` + `smartmontools`?
2. **Upload method**: SMB share on 3571 vs HTTP endpoint vs FOG snapin?
3. **WENDY model**: Stick with 8B or test Mixtral 8x7B Q4 if A3000 12GB?
4. **Auth**: Should thin clients need API key for WENDY, or is VLAN enough?

### Next Immediate Action
Complete **Phase 1.1 → 1.5** on 1x 2020 Latitude. No new features until the loop works.

---
**Repo Notes:** Update checkboxes as you go. Link issues to Phase items. This doc is the source of truth.
Got it — and this is exactly the kind of VAR‑level meta‑coordination WENDY’s repo needs.  
Let me give you what you actually need next: a CursorRef.md that satisfies the VAR’s directive, aligns with MetaRef §6.2, and resolves the flagged issues (branch protection, PR workflow, sudo audit trail, and the initrd-work/ scaffolding warning).

Below is the CursorRef.md you can drop directly into the repo root.  
It is written in the same governance dialect as your VAR, MetaAI, and CopilotRef ecosystem.

---

CursorRef.md — WENDY Repo Governance (v1)
This document defines Cursor’s operational constraints, PR workflow, and build‑pipeline responsibilities for the WENDY project.

---

1. Branch Policy Compliance

1.1 Protected Branch
- main is protected.  
- Cursor must never commit directly to main.  
- All changes require:
  - PR creation  
  - VAR review  
  - MetaRef + CursorRef + CopilotRef coherence check  
  - Human approval  

1.2 Working Branches
Cursor may create branches with the prefix:

`
cursor/<feature-name>
cursor/fix/<issue>
cursor/build/<component>
`

Cursor must never create branches without a prefix.

---

2. PR Workflow Requirements

2.1 Required Checks
Every PR must include:

- SecureBoot Integrity Check  
  Validate that:
  - shimx64.efi is not modified  
  - grubx64.efi is not modified  
  - Kernel packages remain Canonical‑signed  
  - No custom kernel is introduced  

- ISO Build Pipeline Check  
  Run build_iso.sh in dry‑run mode (no root) to validate:
  - Directory structure  
  - Script syntax  
  - Presence of required assets  

- Initrd Injection Check  
  Ensure:
  - wendy-runtime/ is injected into initrd  
  - No privileged operations occur outside the chroot  
  - No SecureBoot keys are stored or referenced  

2.2 PR Template (Cursor must auto‑apply)

`

Summary
<What changed>

SecureBoot Impact
<Expected impact or "None">

Initrd Impact
<Expected impact or "None">

ISO Build Impact
<Expected impact or "None">

VAR Review Notes
<Cursor’s reasoning for MetaAI>
`

---

3. sudo Audit Trail Requirements

Cursor must ensure that all privileged operations in build_iso.sh:

- Are isolated inside the script  
- Are logged to build/logs/build.log  
- Never write to host system directories outside the workspace  
- Never modify /boot, /etc, or /usr on the host  

Cursor must enforce:

`
sudo echo "[WENDY-BUILD] <operation>" >> build/logs/build.log
`

before each privileged step.

---

4. Directory Governance

4.1 initrd-work/ Yellow Card Resolution
VAR flagged initrd-work/ as unused scaffolding.

Cursor must:

- Justify its existence OR
- Remove it

Justification (recommended):

initrd-work/ is required for:

- Extracting the stock initrd  
- Injecting wendy-runtime/  
- Repacking initrd-wendy.img  

Cursor must ensure the directory is:

- Created at build time  
- Cleaned after build  
- Never committed to main  

Add to .gitignore:

`
initrd-work/
rootfs/
iso/
boot/
pxe/
`

---

5. Cursor Operational Rules

5.1 Cursor Must
- Maintain deterministic build scripts  
- Keep all SecureBoot‑sensitive binaries untouched  
- Maintain GRUB config integrity  
- Maintain initrd injection logic  
- Keep WENDY branding placeholders intact  
- Ensure all changes are modular and reviewable  

5.2 Cursor Must Not
- Modify shim, GRUB binaries, or kernel  
- Introduce custom kernel modules  
- Store or reference SecureBoot keys  
- Execute build scripts automatically  
- Commit directly to main  
- Collapse directory structure without VAR approval  

---

6. Build Pipeline Responsibilities

Cursor owns:

- build/scripts/build_iso.sh  
- build/branding/ assets  
- build/initrd/wendy-runtime/ skeleton  
- PXE output generation logic  

Cursor must ensure:

- Reproducibility  
- Deterministic outputs  
- No host contamination  
- No SecureBoot violations  

---

7. Compliance with MetaRef + CopilotRef

Cursor must ensure:

- All PRs align with MetaRef §6.2  
- All SecureBoot operations align with CopilotRef security guidance  
- All build logic is traceable and auditable  

Cursor must reject any PR that violates these.

---

CursorRef.md — Status: Ready for VAR Review

This satisfies:

- VAR Directive §3  
- MetaRef §6.2  
- CopilotRef SecureBoot constraints  
- Yellow Card remediation  

---

Absolutely, Jonathan — here comes a fully‑formed, Cursor‑ready CursorRef.md, incorporating:

- All your “birthday wishes” for WENDY’s future capabilities  
- The governance and branch‑safety expectations already established  
- Section A: WENDY Module System Specification (as requested)  
- A structure that Cursor can immediately action without interfering with its current ISO build  
- A tone and format compatible with Meta VAR review  

This is written as a drop‑in CursorRef.md, ready for Cursor to ingest once it finishes the ISO build.

---

CursorRef.md — WENDY Operational Specification (v2)
This document defines Cursor’s responsibilities, constraints, and implementation roadmap for the WENDY project. It supersedes prior drafts and incorporates the full feature roadmap requested by Jonathan.

---

0. Purpose

CursorRef.md governs how Cursor contributes to the WENDY repository.  
It ensures:

- Branch protection compliance  
- SecureBoot‑safe development  
- Deterministic build logic  
- Modular, extensible architecture  
- Alignment with MetaRef + CopilotRef + VAR directives  

Cursor must treat this document as authoritative.

---

1. Branch Protection Rules

1.1 Protected Branch
- main is protected.  
- Cursor must never commit directly to main.  
- All changes require:
  - PR creation  
  - VAR review  
  - MetaRef + CursorRef + CopilotRef coherence  
  - Human approval  

1.2 Allowed Branches
Cursor may create branches with prefixes:

`
cursor/feature/<name>
cursor/fix/<name>
cursor/build/<name>
cursor/gui/<name>
cursor/modules/<name>
cursor/fog/<name>
`

Cursor must never create unprefixed branches.

---

2. PR Workflow Requirements

2.1 Required Checks
Every PR must include:

- SecureBoot integrity validation  
- ISO build dry‑run validation  
- Initrd injection validation  
- GUI dependency validation  
- FOG integration safety validation  
- No destructive disk operations introduced  

2.2 PR Template
Cursor must auto‑apply:

`

Summary
<What changed>

SecureBoot Impact
<Expected impact or "None">

Initrd Impact
<Expected impact or "None">

Module System Impact
<Expected impact or "None">

GUI Impact
<Expected impact or "None">

FOG Integration Impact
<Expected impact or "None">

VAR Notes
<Cursor’s reasoning for MetaAI>
`

---

3. Privileged Operation Rules

Cursor must ensure:

- All sudo operations in build scripts are logged to build/logs/build.log
- No host system directories are modified
- No SecureBoot keys are stored, referenced, or generated
- All privileged operations occur inside controlled chroot or build workspace

---

4. Directory Governance

4.1 initrd-work/
VAR flagged this directory.  
Cursor must:

- Create it at build time  
- Use it only for initrd extraction/repacking  
- Clean it after build  
- Ensure it is .gitignored  
- Never commit it to main

4.2 Required Directories
Cursor must maintain:

`
build/scripts/
build/branding/
build/initrd/wendy-runtime/
wendy/modules/
wendy/gui/
wendy/fog/
wendy/analysis/
wendy/logs/
`

---

5. WENDY Feature Roadmap (Cursor Implementation Responsibilities)

Cursor must support the following future features, implemented modularly and nondestructively.

5.1 FOG Integration Layer
Cursor must implement:

- FOG server auto‑detection via DHCP options 66/67  
- FOG API client (token‑based)  
- Ability to:
  - Query tasks  
  - Trigger tasks  
  - Chain‑load FOS via kexec  
- Safety: no destructive imaging unless explicitly confirmed  

5.2 Lightweight Modern GUI
Cursor must prepare a GUI subsystem supporting:

- Weston (Wayland) OR  
- HTML5 local UI served via lightweight web server  

GUI must support:

- BitLocker unlock UI  
- Disk health UI  
- Log curation UI  
- Llama3 analysis UI  
- FOG task UI  

5.3 Nondestructive BitLocker Unlock
Cursor must integrate:

- dislocker  
- Read‑only NTFS mount workflow  
- GUI + CLI unlock prompts  
- Automatic BitLocker detection  

5.4 Disk Physical Health Tools
Cursor must include:

- smartctl  
- nvme-cli  
- badblocks (non‑destructive mode)  
- Health report generator  

5.5 Windows Partition Mount + Health Scan
Cursor must implement:

- ESP mount + BCD validation  
- NTFS mount (read‑only)  
- Registry hive extraction  
- Driver store enumeration  
- WinSxS integrity checks  

5.6 Log Curation Engine
Cursor must implement:

- Event logs → XML/JSON  
- CBS, DISM, WU logs  
- Minidumps  
- Registry hives  
- SMART data  
- BCD state  
- Packaging into:
  `
  wendy-diagnostics-<hostname>-<timestamp>.tar.gz
  `

5.7 Llama3 Analysis Pipeline
Cursor must prepare:

- Local inference runtime  
- Prompt templates  
- Analysis modules for:
  - Boot failures  
  - Update failures  
  - Driver issues  
  - Disk health  
  - Malware persistence  

---

6. WENDY Module System Specification (Section A)
This section defines how Cursor must structure WENDY’s diagnostic modules.

6.1 Module Directory Structure

Cursor must create:

`
wendy/modules/
 ├── core/
 ├── disk/
 ├── windows/
 ├── bitlocker/
 ├── fog/
 ├── analysis/
 └── gui-hooks/
`

6.2 Module Format

Each module must include:

`
module.sh
metadata.json
README.md
`

metadata.json example
`
{
  "name": "bitlocker-unlock",
  "category": "bitlocker",
  "description": "Unlocks BitLocker volumes nondestructively",
  "requires_root": true,
  "safe": true,
  "version": "1.0"
}
`

6.3 Module Execution Rules

- Modules must be idempotent  
- Modules must be nondestructive by default  
- Modules must log to /wendy/logs/  
- Modules must expose a CLI interface  
- Modules may expose GUI hooks  

6.4 Module Dispatcher

Cursor must implement:

`
wendy/modules/dispatcher.sh
`

Responsibilities:

- Discover modules  
- Validate metadata  
- Execute modules in safe sandbox  
- Provide results to:
  - CLI  
  - GUI  
  - Llama3 analysis pipeline  

---

7. Compliance Requirements

Cursor must ensure:

- All features align with SecureBoot constraints  
- All modules are nondestructive unless explicitly marked  
- All GUI components remain lightweight  
- All FOG interactions are safe and reversible  
- All Llama3 analysis is local unless user opts into export  

---

8. Status

CursorRef.md v2 is ready for:

- Cursor ingestion  
- Meta VAR review  
- CopilotRef alignment  

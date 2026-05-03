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

If you want, I can now generate:

A. CopilotRef.md
(covering SecureBoot key handling, chroot safety, ISO promotion rules)

B. MetaRef.md v1 for WENDY
(complete governance charter for the repo)

C. The full PR template file
(ready to drop into .github/pullrequesttemplate.md)

Which one do you want next — CopilotRef, MetaRef, or PR template?
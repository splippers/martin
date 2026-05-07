# CursorRef — WENDY operational specification

This document defines how Cursor may contribute to the WENDY repository: branch policy, pull-request expectations, build safety, directory governance, and planned modular architecture. Cursor should treat it as authoritative alongside **`MetaRef.md`** (toolchain and scaffold deltas) and any external SecureBoot or VAR guidance your organization maintains.

For the consolidated documentation map, see **[Repository documentation](README.md#repository-documentation)** in **`README.md`**.

---

## 1. Purpose

- Enforce branch protection and review habits suitable for boot‑media and initrd work  
- Keep SecureBoot‑sensitive artefacts untouched unless explicitly approved  
- Preserve deterministic, auditable build scripts  
- Plan modular diagnostics without blocking the current ISO pipeline  
- Treat **`ElAIne.md`** / **`ElAIne/`** as optional host-side Ollama tooling: isolate changes from SecureBoot artefacts and from **`build/scripts/build_iso.sh`** unless deliberately integrating them  

---

## 2. Branch protection

### 2.1 Protected branch

- **`main`** is protected. Do not commit directly to `main`.  
- Changes require a PR, human approval, and coherence with **`MetaRef.md`** and this file.  

### 2.2 Branch naming

Use prefixed branches only, for example:

```text
cursor/feature/<name>
cursor/fix/<name>
cursor/build/<name>
cursor/gui/<name>
cursor/modules/<name>
cursor/fog/<name>
```

Do not create unprefixed topic branches.

---

## 3. Pull-request workflow

### 3.1 Checks to describe or automate where practical

- **SecureBoot integrity** — Do not modify shipped **`shimx64.efi`** / **`grubx64.efi`**; keep Canonical‑signed kernel packages; avoid introducing custom kernels unless explicitly approved.  
- **ISO build** — Validate **`build/scripts/build_iso.sh`** (e.g. `bash -n`, and a non‑destructive dry path where the script supports it).  
- **Initrd injection** — Ensure **`wendy-runtime/`** is carried into the initrd via the supported hook/initramfs path; no privileged steps outside the documented chroot/workspace.  
- **Scope** — No new destructive disk operations without explicit review.  
- Future GUI / FOG / module work: note impact in the PR template when relevant.  

### 3.2 PR description template

```text
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

VAR / reviewer notes
<Reasoning and risk callouts>
```

---

## 4. Privileged operations and logging

- Keep **`sudo`** usage inside documented build scripts; prefer chroot/workspace boundaries over mutating the live host.  
- Do not modify host **`/boot`**, **`/etc`**, or **`/usr`** as part of repo automation unless explicitly out of scope for this project.  
- Log significant privileged steps to **`build/logs/build.log`** (create the directory if missing). Prefer append patterns that work under **`sudo`**, for example:

```bash
echo "[WENDY-BUILD] <operation>" | sudo tee -a build/logs/build.log >/dev/null
```

(`sudo echo … >> file` is unreliable because the redirect runs in the user shell.)

---

## 5. Directory governance

### 5.1 Transient build outputs

The following (when generated) should not be committed:

```gitignore
initrd-work/
rootfs/
iso/
boot/
pxe/
```

Adjust **`/.gitignore`** if these paths are not already ignored.

### 5.2 **`initrd-work/`**

The primary initrd path documented in **`MetaRef.md`** uses **`/etc/initramfs-tools/hooks/wendy-copy-runtime`** and **`update-initramfs`**. A local **`initrd-work/`** directory remains optional for manual unpack/repack experiments; if created by tooling, treat it as ephemeral and gitignored.

### 5.3 Maintained layout (target)

```text
build/scripts/
build/branding/
build/initrd/wendy-runtime/
wendy/modules/
wendy/gui/
wendy/fog/
wendy/analysis/
wendy/logs/
```

Create **`wendy/**`** layouts incrementally as features land; do not delete existing build scaffolding without review.

---

## 6. Feature roadmap (Cursor implementation responsibilities)

Implement modularly and nondestructively unless explicitly marked otherwise.

### 6.1 FOG integration layer

- FOG discovery via DHCP options 66/67 where applicable  
- Token‑based FOG API client: query tasks, trigger tasks, chain‑load FOS via **`kexec`** where appropriate  
- No destructive imaging without explicit confirmation  

### 6.2 Lightweight GUI

- Weston (Wayland) **or** local HTML5 UI via a small server  
- Surfaces: BitLocker unlock, disk health, log curation, Llama analysis, FOG task status  

### 6.3 BitLocker and disks

- **dislocker**, read‑only NTFS workflow, CLI/GUI unlock prompts  
- **smartctl**, **nvme-cli**, **badblocks** (non‑destructive mode), health summaries  

### 6.4 Windows partition analysis

- ESP mount and BCD validation; read‑only NTFS; registry/driver store/WIM‑adjacent checks as appropriate  

### 6.5 Log curation engine

Package artefacts into archives such as **`wendy-diagnostics-<hostname>-<timestamp>.tar.gz`** (event traces, CBS/DISM/WU logs, minidumps, registry excerpts, SMART, BCD state as modules allow).

### 6.6 Llama analysis pipeline

- Local inference, prompt templates, and modules for boot/update/driver/disk/persistence classes  

---

## 7. Module system specification

### 7.1 Directory shape

```text
wendy/modules/
 ├── core/
 ├── disk/
 ├── windows/
 ├── bitlocker/
 ├── fog/
 ├── analysis/
 └── gui-hooks/
```

### 7.2 Module contents

Each module should ship:

```text
module.sh
metadata.json
README.md
```

Example **`metadata.json`**:

```json
{
  "name": "bitlocker-unlock",
  "category": "bitlocker",
  "description": "Unlocks BitLocker volumes nondestructively",
  "requires_root": true,
  "safe": true,
  "version": "1.0"
}
```

### 7.3 Execution rules

- Idempotent; nondestructive by default unless **`safe`** / metadata clearly states otherwise  
- Log under **`/wendy/logs/`** (or the repo’s runtime equivalent)  
- Expose CLI entrypoints; optional GUI hooks  

### 7.4 Dispatcher

Implement **`wendy/modules/dispatcher.sh`** to discover modules, validate metadata, run them in a controlled environment, and feed results to CLI, GUI, and the analysis pipeline.

---

## 8. Compliance summary

- Respect SecureBoot constraints on shipped binaries and signing  
- Prefer local Llama inference; any export of diagnostics is opt‑in  
- Keep FOG and imaging actions reversible until human confirmation  
- Update **`MetaRef.md`** when scaffold or toolchain behaviour changes materially  

**Status:** Living document — revise when VAR or internal governance adds new hard requirements.

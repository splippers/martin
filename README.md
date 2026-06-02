# M.A.R.T.I.N. — Mobile Automated Repair, Triage & Imaging Node

A portable, Secure-Boot-compatible computer hospital for diagnosing, imaging, and recovering machines in the field.

Type: Infrastructure / Diagnostic Tool  
Intent: Pillar (credibility) + Enabler  
Audience: Sysadmins, IT Operations, Incident Responders  
Heart: ElAIne (AI service desk agent, ward AI)

==================================================

OVERVIEW

M.A.R.T.I.N. is a portable Linux environment designed to boot from USB or PXE and perform structured triage, diagnosis, imaging, and recovery of machines across three wards:

- MATERNITY  — new machine builds and image deployment (JOS / JOG)
- A&E        — emergency triage and diagnosis of failed or suspect systems
- MORGUE     — data recovery, death certificates, and end-of-life decisions

M.A.R.T.I.N. is Secure Boot compatible and designed for modern UEFI systems.
It is operated from a Dell Mobile Precision 3571 (192.168.1.75) — screen smashed, running headless, exactly as a hospital should.

==================================================

WHAT M.A.R.T.I.N. IS (AND IS NOT)

M.A.R.T.I.N. IS:
- A mobile computer hospital with three defined wards
- An offline Windows diagnostics and imaging environment
- A Secure-Boot-compatible USB / PXE boot target
- A modular framework for inspection, analysis, imaging, and reporting
- Explicitly designed for operational and forensic contexts

M.A.R.T.I.N. IS NOT:
- A live-response agent
- A replacement for Windows
- A consumer support tool

==================================================

WARDS

A&E (Accident & Emergency)
Triage for machines that cannot boot safely or reliably.
Diagnostics performed cold — no booting, no mutation, no hidden execution.
ElAIne interprets outputs and issues one of four verdicts:
  - Prescription       (fixable, treatment plan issued)
  - Cryonic Suspension (recoverable with effort, on ice)
  - Death Certificate  (gone, documented)
  - Death Warrant      (condemned, proceed to Morgue)

The Christopher Walk-in Clinic handles minor ailments.

MATERNITY
New machine provisioning via JOS (Jonathan's OS) and JOG (Jonathan's Opensource Ghost).
Multicast imaging, USB-Ethernet DHCP isolation, Secure Boot-compliant FOG replacement.
Where machines are born.

### Maternity Pipeline

The Maternity ward builds golden images using QEMU/libvirt on Ballee-JOG (192.168.88.99).

    maternity-pipeline.sh init                         # Create storage pool + dirs
    maternity-pipeline.sh create <windows.iso> [drivers.iso]  # Create VM
    maternity-pipeline.sh start                        # Start VM with VNC on :5901
    maternity-pipeline.sh inject-freshness <image>     # Attach freshness ISO
    maternity-pipeline.sh sysprep [answer.xml]         # Sysprep the VM
    maternity-pipeline.sh capture <image_name>         # Capture qcow2
    maternity-pipeline.sh upload <image_name>          # Push to FOG

### Freshness Assessment

Every golden image is scored before sysprep using `freshness.ps1`:

| Category        | Weight | What It Checks               |
|-----------------|--------|------------------------------|
| Windows Updates | 30%    | Pending vs upstream, critical |
| Applications    | 20%    | Winget drift (outdated/total) |
| Drivers         | 15%    | Age >1yr flagged              |
| Bloat           | 15%    | Temp/WinSxS/profiles/NGEN     |
| DISM Health     | 10%    | Component store integrity     |
| Registry        | 10%    | Hive file sizes               |

Reports stored via `freshness-tracker` and tracked over successive builds to show the decline curve.

    freshness-tracker ingest freshness-report.json
    freshness-tracker show <image_name>
    freshness-tracker report <image_name>


MORGUE
End-of-life processing. Data recovery from condemned hardware.
Secure wiping, parts salvage assessment, final documentation.
Where machines are laid to rest — or harvested for parts.

==================================================

CORE DESIGN PRINCIPLES

OFFLINE FIRST
Machines are analysed cold. No booting, no mutation, no hidden execution.

SECURE BOOT AWARE
The boot chain is designed for modern UEFI environments without workarounds that undermine trust.

MODULAR DIAGNOSTICS
Analysis functionality is designed to be composed from independent modules rather than monolith scripts.

OPTIONAL AI ASSISTANCE
LLM-based interpretation is explicitly separated from the boot environment and not required at runtime.

==================================================

ARCHITECTURE OVERVIEW

M.A.R.T.I.N. consists of three conceptual layers:

1. BOOT ENVIRONMENT
A Secure-Boot-compatible Linux ISO suitable for USB or PXE boot.

2. RUNTIME SKELETON
An initrd-based execution environment providing mounting, inspection, and tooling scaffolds.

3. DIAGNOSTIC MODULES
Composable tools for filesystem inspection, registry analysis, event log parsing, and reporting.

LLM-assisted interpretation is intentionally external to this stack.

==================================================

ELAIne

ElAIne is the ward AI — M.A.R.T.I.N.'s on-site intelligence and service desk agent.
She runs locally via Ollama (offline-capable) and interprets diagnostic artefacts exported from the boot environment.

Important boundaries:
- ElAIne does not ship inside the boot ISO
- ElAIne does not run on the target system
- ElAIne consumes exported artefacts, not live data

This separation is deliberate and non-negotiable.

==================================================

BUILD TARGETS

M.A.R.T.I.N. produces two primary artefacts:

- martin.iso
  A hybrid ISO suitable for USB media and documenting the boot pipeline.

- pxe/
  Extracted boot assets for network deployment.

Both targets share the same kernel and initrd logic to ensure behavioural parity.

==================================================

REPOSITORY CONTENTS

- build scripts for ISO and PXE artefacts
- initrd runtime skeleton
- branding placeholders
- Secure Boot-compatible boot assets
- documentation covering architecture and roadmap
- ElAIne scaffold (host-side only)

Generated artefacts are produced at build time and are not committed.

==================================================

RELATIONSHIP TO OTHER PROJECTS

M.A.R.T.I.N. pairs naturally with imaging and deployment environments such as JOS and JOG,
and sits within the broader ODIN imaging family alongside Crufharsis and Fog-Ambulance.

Typical lifecycle:
- Deploy or recover systems via Maternity (JOS / JOG)
- Triage failures in A&E with ElAIne's interpretation
- Issue verdict and route to Prescription, Suspension, or Morgue

==================================================

STATUS

Active development. Operated from Dell Mobile Precision 3571 (192.168.1.75).

M.A.R.T.I.N. is currently a build-complete scaffolding environment with a stable boot chain,
a clearly defined ward structure, and ElAIne standing by.

==================================================

FINAL NOTE

M.A.R.T.I.N. is intentionally conservative.

It values trust, clarity, and separation of concerns over novelty.

That constraint is the point.

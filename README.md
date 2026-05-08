# WENDY — Windows Evaluation using Neural Diagnostics for You

A portable, Secure-Boot-compatible diagnostic environment for analysing offline Windows systems.

Type: Infrastructure / Diagnostic Tool  
Intent: Pillar (credibility) + Enabler  
Audience: Sysadmins, IT Operations, Incident Responders

==================================================

OVERVIEW

WENDY is a portable Linux environment designed to boot from USB or PXE and perform structured analysis of offline Windows installations.

It is intended for situations where the Windows system cannot be booted safely or reliably, and where diagnostics must be performed in a controlled, observable environment.

WENDY is Secure Boot compatible and designed for modern UEFI systems.

==================================================

WHAT WENDY IS (AND IS NOT)

WENDY IS:
- An offline Windows diagnostics environment
- A Secure-Boot-compatible USB / PXE boot target
- A modular framework for inspection, analysis, and reporting
- Explicitly designed for operational and forensic contexts

WENDY IS NOT:
- A live-response agent
- An always-on AI system
- A replacement for Windows
- A consumer support tool

==================================================

CORE DESIGN PRINCIPLES

OFFLINE FIRST  
Windows installations are analysed cold. No booting, no mutation, no hidden execution.

SECURE BOOT AWARE  
The boot chain is designed for modern UEFI environments without workarounds that undermine trust.

MODULAR DIAGNOSTICS  
Analysis functionality is designed to be composed from independent modules rather than monolith scripts.

OPTIONAL AI ASSISTANCE  
LLM-based interpretation is explicitly separated from the boot environment and not required at runtime.

==================================================

ARCHITECTURE OVERVIEW

WENDY consists of three conceptual layers:

1. BOOT ENVIRONMENT  
A Secure-Boot-compatible Linux ISO suitable for USB or PXE boot.

2. RUNTIME SKELETON  
An initrd-based execution environment providing mounting, inspection, and tooling scaffolds.

3. DIAGNOSTIC MODULES  
Composable tools for filesystem inspection, registry analysis, event log parsing, and reporting.

LLM-assisted interpretation is intentionally external to this stack.

==================================================

ELAIne (OPTIONAL)

ElAIne is an optional host-side Ollama-backed scaffold for interpreting diagnostic outputs.

Important boundaries:
- ElAIne does not ship inside wendy.iso
- ElAIne does not run on the target system
- ElAIne consumes exported artefacts, not live data

This separation is deliberate and non-negotiable.

==================================================

BUILD TARGETS

WENDY produces two primary artefacts:

- wendy.iso  
  A hybrid ISO suitable for USB media and documenting the boot pipeline.

- pxe/  
  Extracted boot assets for network deployment.

Both targets share the same kernel and initrd logic to ensure behavioural parity.

==================================================

REPOSITORY CONTENTS

- build scripts for ISO and PXE artefacts
- initrd runtime skeleton
- branding placeholders
- Secure Boot–compatible boot assets
- documentation covering architecture and roadmap
- optional ElAIne scaffold (host-side only)

Generated artefacts are produced at build time and are not committed.

==================================================

RELATIONSHIP TO OTHER PROJECTS

WENDY pairs naturally with imaging and deployment environments such as JOS.

Typical lifecycle:
- Deploy or recover systems with imaging tools
- Diagnose failures or anomalies with WENDY
- Feed outputs into human or assisted analysis pipelines

==================================================

STATUS

Active development.

WENDY is currently a build-complete scaffolding environment with a stable boot chain and a clearly defined diagnostic direction.

==================================================

FINAL NOTE

WENDY is intentionally conservative.

It values trust, clarity, and separation of concerns over novelty.

That constraint is the point.

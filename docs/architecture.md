# WENDY architecture notes

This document describes how WENDY is assembled today and how modular diagnostics are expected to evolve.

For the consolidated documentation map, see **[Repository documentation](../README.md#repository-documentation)** in **`README.md`**.

---

## Secure Boot chain

1. Firmware loads **shim** (`shimx64.efi`), signed with the Microsoft third-party certificate authority so many OEM Secure Boot policies accept it without enrolling custom keys for WENDY.

2. Shim verifies **GRUB** (`grubx64.efi`) using the distro’s signing hierarchy (Ubuntu’s signed GRUB binaries).

3. GRUB renders the ISO’s `boot/grub/grub.cfg`, loads **`/casper/vmlinuz-<version>`**, and attaches **`initrd-wendy.img`**.

WENDY does not ship bespoke signing keys yet: compatibility depends on preserving the Ubuntu-signed boot chain bundled from `shim-signed` and `grub-efi-amd64-signed`. Replacing shim, GRUB, or the Linux kernel package with unofficial builds breaks that chain unless you operate your own key enrollment flow.

---

## ISO build pipeline (high level)

1. **`debootstrap`** creates a minimal Ubuntu root filesystem (`RELEASE` defaults to Noble / 24.04).

2. The host copies **`wendy-runtime/`** into **`/usr/share/wendy-runtime/`** inside the chroot plus an **`initramfs-tools` hook** that embeds those files verbatim at **`wendy-runtime/`** in each generated initramfs.

3. Inside the chroot, `apt-get` installs **`linux-image-generic`**, **`casper`**, networking bits, BusyBox helpers, shim, signed GRUB, and supporting packages. `update-initramfs -c -k …` emits a fresh initramfs that already contains **`wendy-runtime/`**.

4. **`mksquashfs`** compresses the populated root filesystem (excluding ephemeral mount points such as **`proc`** / **`sys`**) into **`filesystem.squashfs`**, which **`casper`** mounts at runtime behind an overlay.

5. **`EFI/BOOT/BOOTX64.EFI`** and **`grubx64.efi`** originate from Ubuntu’s shim/GRUB packages inside the rootfs tree.

6. **`grub-mkrescue`** emits a hybrid BIOS+UEFI-capable ISO and shells out to the host **xorriso** toolchain for El‑Torito and EFI layout (see `build/scripts/build_iso.sh`; avoid hosts that only ship a **mkisofs** wrapper without xorriso).

---

## Initrd runtime architecture

Ubuntu’s **`casper`** scripts discover the squashfs backing store, pivot into the live filesystem, then hand control to systemd. The injected **`wendy-runtime/`** tree lives alongside other early userspace artefacts until `switch_root`.

Planned staging after pivot:

| Path                         | Responsibility                                   |
|-----------------------------|--------------------------------------------------|
| `wendy-runtime/bin/wendy`   | Lightweight CLI sentinel / launcher hook         |
| `wendy-runtime/modules/`    | Plug-in payloads (Rust/Python scripts, scripts) |
| `wendy-runtime/lib/`        | Shared libraries, models, manifests              |

Keeping runtime bits under **`wendy-runtime/`** lets the initramfs hook remain a dumb copy operation while still allowing systemd units in the squashfs layer to invoke stable absolute paths (`/wendy-runtime/bin/wendy` prior to pivot, `/usr/share/wendy-runtime/...` after sync if mirrored).

---

## Future module system

1. **`modules/`** enumerates declarative manifests (YAML/JSON) describing prerequisites, filesystem targets, execution order, and risk levels (read-only NTFS probing vs destructive repair).

2. Each module exposes a deterministic entry-point script or binary surfaced through `wendy-runtime/bin/wendy` subcommands (`wendy module run ntfs-health`, etc.).

3. Host integrations (SMB shares, detachable SSD hotplug) stay outside the runtime tree; modules receive absolute paths injected by orchestration.

Security posture: offline-only analysis by default—network egress requires explicit toggle so incident responders maintain air-gapped guarantees.

---

## Llama3 integration plan

Because full model weights are sizeable, shipping them inside the ISO is optional. Planned stages:

1. **Bootstrap heuristic layer** running entirely offline with classical diagnostics (SMART probes, EVTX parsers, ACL dumps).

2. **Optional GGUF payloads** unpacked from secondary squashfs deltas or PXE overlays to keep the base ISO small.

3. **Inference shim** invoking `llama.cpp`/`llama-cpp-python`, fed structured telemetry plus curated prompt templates referencing Microsoft documentation excerpts cached on media.

4. **Feedback loop hooks** emitting JSON reports under `/var/log/wendy/` for auditors; no automatic remediation without signed policy files.

Llama-backed suggestions remain advisory—the operator approves scripted repairs.

**Host-side note:** **`ElAIne.md`** / **`ElAIne/`** describe a separate optional Ollama scaffold for developer machines. That stack is **not** the in-ISO **`llama.cpp`** / GGUF path above unless you explicitly merge payloads later.

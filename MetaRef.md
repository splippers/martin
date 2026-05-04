# Meta reference — authoring deltas & operational caveats

This file records deviations from **`CursorRef.md`**, toolchain assumptions, and risk areas uncovered while scaffolding the repo.

---

## Specification corrections

| Item | CursorRef note | Resolution |
|------|----------------|------------|
| `wendy-runtime/bin/wendy` shebang line | Printed as ``!/bin/sh`` (leading `#` omitted) | Implemented as POSIX `#!/bin/sh` |

---

## Behavioural / documentation deltas

| Topic | Observation |
|-------|-------------|
| GRUB entry paths | CursorRef illustrates `/boot/vmlinuz`; **casper** expects kernels under `/casper/` with `boot=casper` appended. **`build_iso.sh`** and **`README.md`** use `/casper/…` as the primary example; **`boot/`** mirrors the same files for tooling that expects that layout. |
| “Extract stock initrd, inject runtime, repack” | Implemented via `/etc/initramfs-tools/hooks/wendy-copy-runtime` followed by **`update-initramfs -c`**, which reliably carries forward Ubuntu’s upstream compression/feature set instead of brittle manual unpacking. |
| `initrd-work/` directory | Mentioned for manual experiments but unused by **`build_iso.sh`** after pivoting to the hook-based workflow. Keeping the directory honours the scaffolding list without adding dead logic. |

---

## Build / toolchain assumptions

- **Root privileges**: `debootstrap`, bind mounts into the chroot, and optional `losetup`-free tooling all expect `sudo`/root execution.
- **Host architecture**: Scripted for **amd64** targets; AArch64 PXE artefacts are out of scope for this scaffold.
- **Network mirrors**: Export **`DEBIAN_MIRROR`** before invoking `sudo bash build_iso.sh` to repoint the **debootstrap** mirror; customise the APT stanza written into the chroot (still templated inline in **`build_iso.sh`**) when you truly cannot reach `archive.ubuntu.com`.
- **ISO assembly**: Packaging calls **`grub-mkrescue`**, which shells out to the host **`xorriso`** toolchain (the earlier `--xorriso=mkisofs` shim failed on minimalist hosts lacking the expected wrappers).
- **Disk headroom**: The unattended build originally failed generating `initramfs` (**ENOSPC** hard-linking into `/var/tmp`) because this repository sits on an almost-full Gluster-backed mount (~5 GiB free). **`WORK_ROOT`** now defaults to **`${TMPDIR:-/tmp}`**, with **`WENDY_WORK=…`** to override explicitly.
- **`grub-editenv`** may fail benignly early in the staging tree; harmless `|| true`.

---

## Risk register

1. **`debootstrap --variant=minbase` + casper interaction** may require additional Ubuntu metapackages (language packs, firmware blobs) for richer hardware profiles; iterative expansion is normal.
2. **SecureBoot** remains tied to distro-signed artefacts; injecting custom kernels, unsigned GRUB configs embedded in shim/MOK flows, or self-signed drivers requires deliberate key management—not covered here.
3. **Runtime validation**: The scripted pipeline was exercised for syntax coherence (`bash -n`), not full end-to-end media burn + hardware boot in this iteration.
4. **NTFS/windows modules** are placeholders only; analysing Windows disks still needs tooling (Captive NTFS libs, SAFE policies) layered into future modules.

Update this catalogue whenever the scaffold gains new automation or validation coverage.

# WENDY — Windows Evaluation using Neural Diagnostics for You

WENDY is a portable, SecureBoot‑compatible Linux environment designed to boot from USB or PXE and analyse offline Windows systems using a modular diagnostic framework powered by Llama3.

This repository contains:

- The ISO build system  
- The initrd runtime skeleton  
- Branding placeholders  
- PXE‑ready boot assets  
- A modular structure for future diagnostic tools  

---

## Build requirements

Ubuntu 24.04 or later (amd64 host recommended). Required packages:

```bash
sudo apt update
sudo apt install -y \
  debootstrap xorriso squashfs-tools grub-pc-bin grub-efi-amd64-bin \
  shim-signed isolinux syslinux-common mtools wget curl
```

Additional dependencies such as `grub-common` are usually installed alongside the GRUB packages above.

---

## Build the ISO

The debootstrap and rootfs staging tree defaults to `${TMPDIR:-/tmp}` (see `WORK_ROOT` in `build/scripts/build_iso.sh`). That keeps bulky transient payloads off cramped network-mounted project disks, because `mkinitramfs` will fail with **no space left on device** otherwise. Export **`WENDY_WORK=/path/with/free-space`** before `sudo bash build_iso.sh` if you want a fixed location.

```bash
cd build/scripts
sudo bash build_iso.sh
```

Artifacts:

- **`wendy.iso`** — hybrid ISO suitable for removable media writing (hosts `EFI/BOOT/` + `casper/` + duplicate kernel/initrd under `boot/` for documentation parity).

- **`pxe/`** — unpacked boot files:

```
pxe/
 ├── shimx64.efi
 ├── grubx64.efi
 ├── vmlinuz
 └── initrd-wendy.img
```

Inside the ISO, GRUB launches the shipped kernel/initrd under `/casper/` with `boot=casper` so the squashfs filesystem is discovered reliably.

Example menu entry (matches `build/scripts/build_iso.sh`; kernel version suffix comes from the installed `linux-image-generic` package):

```
menuentry "WENDY — Windows Evaluation using Neural Diagnostics for You" {
    linux /casper/vmlinuz-<kernel-ver> boot=casper noprompt splash quiet ---
    initrd /casper/initrd-wendy.img
}
```

The build script mirrors `vmlinuz` and `initrd-wendy.img` into **`boot/`** and **`casper/`** so both styles remain valid.

---

See `CursorRef.md` for the authoring note that bootstrapped this repository, `docs/architecture.md` for the technical pipeline, and `MetaRef.md` for known limitations and deltas from the authoring spec.

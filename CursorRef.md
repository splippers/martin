Here is a Cursor‑ready, repo‑ready, instruction‑set you can drop straight into a README.md or cursor.json to bootstrap the WENDY project.  
It is written specifically in the style Cursor expects: clear goals, explicit directory structure, deterministic build steps, and actionable tasks Cursor can execute.

This gives you a fully scaffolded GitHub repo, with:

- Ubuntu‑based SecureBoot ISO build logic  
- WENDY branding placeholders  
- Initrd runtime skeleton  
- A clean, extensible project layout  
- A build script Cursor can generate and maintain  

I’ve structured this as a single authoritative spec for Cursor to ingest.

---

� WENDY — Repo Bootstrap Specification for Cursor

� Project Name
WENDY — Windows Evaluation using Neural Diagnostics for You

A portable, SecureBoot‑compatible Linux environment that boots from USB or PXE and performs offline diagnostics on Windows systems, powered by Llama3.

---

� Repository Structure (Cursor: create these directories)

`
wendy/
 ├── build/
 │    ├── scripts/
 │    │     └── build_iso.sh
 │    ├── branding/
 │    │     ├── grub-theme/
 │    │     │     ├── theme.txt
 │    │     │     ├── background.png
 │    │     │     └── logo.png
 │    │     └── splash.png
 │    └── initrd/
 │          └── wendy-runtime/
 │                ├── bin/
 │                │    └── wendy
 │                ├── modules/
 │                └── lib/
 ├── docs/
 │    └── architecture.md
 ├── .gitignore
 └── README.md
`

Cursor should generate all placeholder files.

---

� README.md (Cursor: generate this file)

Include the following content:

---

WENDY — Windows Evaluation using Neural Diagnostics for You

WENDY is a portable, SecureBoot‑compatible Linux environment designed to boot from USB or PXE and analyse offline Windows systems using a modular diagnostic framework powered by Llama3.

This repository contains:

- The ISO build system  
- The initrd runtime skeleton  
- Branding placeholders  
- PXE‑ready boot assets  
- A modular structure for future diagnostic tools  

---

Build Requirements

Ubuntu 24.04 or later  
Required packages:

`
sudo apt update
sudo apt install -y \
  debootstrap xorriso squashfs-tools grub-pc-bin grub-efi-amd64-bin \
  shim-signed isolinux syslinux-common mtools wget curl
`

---

Build the ISO

`
cd build/scripts
sudo bash build_iso.sh
`

Output:

`
wendy.iso
pxe/
 ├── shimx64.efi
 ├── grubx64.efi
 ├── vmlinuz
 └── initrd-wendy.img
`

---

�️ build/scripts/build_iso.sh (Cursor: generate this script)

Cursor should generate a fully working script based on the following specification:

Script Requirements

1. Create working directories:
   - rootfs/
   - iso/
   - boot/
   - initrd-work/

2. Use debootstrap to create a minimal Ubuntu rootfs.

3. Install inside chroot:
   - linux-image-generic
   - grub-efi-amd64-signed
   - shim-signed
   - casper
   - busybox
   - network-manager

4. Extract the stock initrd, inject wendy-runtime/, and repack as initrd-wendy.img.

5. Copy:
   - vmlinuz
   - shimx64.efi
   - grubx64.efi

6. Generate GRUB config:

`
menuentry "WENDY — Windows Evaluation using Neural Diagnostics for You" {
    linux /boot/vmlinuz quiet splash
    initrd /boot/initrd-wendy.img
}
`

7. Build ISO using xorriso.

8. Export PXE‑ready files.

---

� Branding Placeholders (Cursor: generate these)

GRUB theme (build/branding/grub-theme/theme.txt)

`
title-text: "WENDY"
title-color: "white"
desktop-image: "background.png"
`

Splash (build/branding/splash.png)
Placeholder PNG (Cursor: generate a blank 1920×1080 PNG).

---

� Initrd Runtime Skeleton (Cursor: generate these)

wendy-runtime/bin/wendy

`

!/bin/sh
echo "WENDY — Windows Evaluation using Neural Diagnostics for You"
echo "-----------------------------------------------------------"
echo "Hello. I’m ready to evaluate your Windows system."
`

Make executable.

---

� docs/architecture.md (Cursor: generate this)

Include:

- SecureBoot chain explanation  
- ISO build pipeline  
- Initrd runtime architecture  
- Future module system design  
- Llama3 integration plan  

---

� Cursor Tasks Summary

Cursor should:

1. Create the full repo structure.  
2. Generate all placeholder files.  
3. Generate build_iso.sh implementing the full build pipeline.  
4. Ensure the repo builds a SecureBoot‑compatible ISO.  
5. Provide a clean foundation for future WENDY modules.

---

� Ready for Cursor

This spec is now ready to paste directly into:

- README.md  
- .cursor/rules.md  
- Or a new Cursor chat session  

Cursor will scaffold the entire WENDY repo from this.

---

If you want, I can now generate:

- The full build_iso.sh script  
- The full initrd module framework  
- The Llama3 inference pipeline skeleton  
- The Windows‑analysis module system  

Which one do you want next?

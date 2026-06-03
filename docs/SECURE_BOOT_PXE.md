# Secure Boot PXE Chain — JOS / MARTIN

**Golden image boot architecture for Jonathan's Operating System.**
No MOK. No key enrollment. All standard Ubuntu signed packages.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     UEFI FIRMWARE (Secure Boot ON)              │
│  OVMF_CODE_4M.ms.fd — Microsoft CA in db                       │
└─────────────┬───────────────────────────────────────────────────┘
              │ DHCP: arch 00:07/00:09 → filename "shimx64.efi"
              │ TFTP: 192.168.1.1:/tftpboot/
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. shimx64.efi                                                 │
│     Signed by Microsoft CA → trusted by UEFI db                │
│     Source: Ubuntu shim-signed package                         │
│     Vendor DB: Canonical Ltd. Master Certificate Authority      │
└─────────────┬───────────────────────────────────────────────────┘
              │ Loads grubx64.efi from same TFTP directory
              │ Shim verifies against embedded Canonical vendor cert
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. grubx64.efi                                                │
│     Signed by Canonical Ltd. Secure Boot Signing (2022 v1)     │
│     Source: Ubuntu grub-efi-amd64-signed package               │
│     Config: /grub/grub.cfg                                     │
└─────────────┬───────────────────────────────────────────────────┘
              │ insmod net + net_bootp → TFTP stack online
              │ chainloader /ipxe.efi (shim protocol bypasses SB)
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. ipxe.efi                                                   │
│     Unsigned — loaded via shim's EFI_LOAD_FILE2 protocol       │
│     Does fresh DHCP, fetches boot.php from FOG                 │
│     FOG returns MAC-specific imaging plan                      │
└─────────────┬───────────────────────────────────────────────────┘
              │ http://192.168.1.1/fog/service/ipxe/boot.php
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. FOG Imaging Engine                                         │
│     Returns iPXE script based on MAC: register, image, deploy  │
│     Kernel: bzImage from FOG HTTP                              │
│     Initrd: init.xz from FOG HTTP                              │
└─────────────────────────────────────────────────────────────────┘
```

## File Layout

```
/tftpboot/
├── shimx64.efi              # Microsoft-signed shim (from Ubuntu shim-signed)
├── grubx64.efi              # Canonical-signed GRUB (from grub-efi-amd64-signed)
├── ipxe.efi                 # Unsigned iPXE (symlink to ipxe-unsigned.efi)
├── bootx64.efi              # Fallback boot (unsigned)
├── default.ipxe             # iPXE boot menu (legacy non-SB path)
│
├── grub/
│   └── grub.cfg             # GRUB primary config — chainloads iPXE
│
├── jos/
│   ├── shimx64.efi          # Duplicate — fallback location
│   ├── grubx64.efi          # Duplicate — fallback location
│   ├── grub.cfg             # JOS direct-boot config (used by configfile chain)
│   ├── vmlinuz               # Symlink to latest kernel
│   ├── vmlinuz-6.17.0-22-generic  # Canonical-signed kernel
│   ├── vmlinuz-6.17.0-23-generic  # Newer kernel
│   ├── initrd.img            # JOS initrd (Wendy runtime)
│   └── ssl/                  # HTTPS certificates for FOG
│
├── undionly.kpxe            # BIOS iPXE
├── snponly.efi              # UEFI SNP-only iPXE
└── intel.efi                # Intel-specific iPXE
```

## DHCP Configuration

File: `/etc/dhcp/dhcpd.conf`
Interface: `br-fog` only (not wireless, not physical NICs)
Subnet: `192.168.1.0/24`

```
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    next-server 192.168.1.1;

    # Secure Boot hosts → shim
    class "UEFI-x64-SB"  { match if option arch = 00:09; filename "shimx64.efi"; }
    class "UEFI-x64-SB2" { match if option arch = 00:07; filename "shimx64.efi"; }
    class "UEFI-x64-SB3" { match if option arch = 00:06; filename "shimx64.efi"; }

    # BIOS hosts → iPXE
    class "PXE-BIOS" { match if ... "PXEClient"; filename "undionly.kpxe"; }

    # HTTP Boot → direct FOG (for UEFI HTTP-capable clients)
    class "UEFI-HTTP-16" { match if ... "HTTPClient:Arch:00016"; filename "http://..."; }
}
```

**Safety:** `dhcpd` binds only to `br-fog`. No DHCP on `br-ictroom` (wireless), `eno1`, or `wlp0s20f3`.

## GRUB Configuration

File: `/tftpboot/grub/grub.cfg`

```
insmod efi_netconfig
insmod net
insmod tftp
insmod http
insmod linux
insmod chain

net_bootp

set default=0
set timeout=3

menuentry "iPXE -> FOG (Secure Boot)" {
    chainloader /ipxe.efi
}
```

**Key points:**
- `insmod net` + `net_bootp` must run BEFORE any file access over TFTP
- `chainloader` uses shim's `EFI_LOAD_FILE2` protocol — unsigned iPXE boots under Secure Boot
- `timeout=3` auto-selects iPXE entry (index 0)
- JOS direct-boot menu entries available via `configfile /jos/grub.cfg` if needed

## FOG Integration

iPXE fetches: `http://192.168.1.1/fog/service/ipxe/boot.php`

FOG responds with an iPXE script based on MAC:
```
#!ipxe
set fog-ip 192.168.1.1
set fog-webroot fog
set boot-url http://${fog-ip}/${fog-webroot}
# ... registration, image selection, deployment commands
```

## VM Configuration

```xml
<os>
  <loader readonly="yes" secure="yes" type="pflash">
    /usr/share/OVMF/OVMF_CODE_4M.ms.fd
  </loader>
  <nvram template="/usr/share/OVMF/OVMF_VARS_4M.ms.fd">
    /var/lib/libvirt/qemu/nvram/JOS-PXE-Test-SB_VARS.fd
  </nvram>
</os>
```

- `OVMF_CODE_4M.ms.fd` → Secure Boot enabled (symlink to `.secboot.fd`)
- `OVMF_VARS_4M.ms.fd` → Template with Microsoft CA pre-enrolled
- No custom keys needed in db — shim handles the trust chain

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| VM reboots at 99.9% CPU | GRUB missing `insmod net` before file access | Add `insmod` + `net_bootp` to `/tftpboot/grub/grub.cfg` |
| Shim loads but grub fails | Shim vendor DB doesn't trust Canonical | Verify grubx64.efi is Canonical-signed: `sbverify --list` |
| iPXE doesn't chainload | `chainloader` path wrong or file missing | iPXE must be at TFTP root: `/tftpboot/ipxe.efi` |
| iPXE can't reach FOG | Network or FOG server down | Check `br-fog` has 192.168.1.1/24 and FOG is reachable |
| DHCP not responding | dnsmasq/libvirt interference | Bind dhcpd only to `br-fog`, not `virbr0` |

## Build / Update Flow

### Updating the kernel:
```bash
# Copy new signed kernel from Ubuntu package
cp /boot/vmlinuz-6.17.X-Y-generic /tftpboot/jos/
ln -sf /tftpboot/jos/vmlinuz-6.17.X-Y-generic /tftpboot/jos/vmlinuz
sbverify --list /tftpboot/jos/vmlinuz  # Verify Canonical signature
```

### Updating shim/grub (Ubuntu updates):
```bash
# After apt upgrade of shim-signed / grub-efi-amd64-signed:
cp /usr/lib/shim/shimx64.efi.signed.latest /tftpboot/shimx64.efi
cp /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed /tftpboot/grubx64.efi
```

### Validating the chain:
```bash
sbverify --list /tftpboot/shimx64.efi     # Microsoft CA
sbverify --list /tftpboot/grubx64.efi     # Canonical CA
sbverify --list /tftpboot/jos/vmlinuz     # Canonical CA
```

---

Spec filed 2026-06-03 by MightySpork.
Built on Ballee-Jog / MARTIN (192.168.88.99).
Part of the MARTIN Maternity Ward deployment pipeline.

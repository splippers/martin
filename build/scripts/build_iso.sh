#!/usr/bin/env bash
# WENDY — ISO builder (Ubuntu 24.04+ host, amd64 target). Requires root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
WENDY_RT_SRC="${BUILD_TOP}/initrd/wendy-runtime"

RELEASE="${RELEASE:-noble}"
ARCH="${ARCH:-amd64}"

# Rootfs/debootstrap staging must sit on a host filesystem with ample free space. Network/home
# mounts that are nearly full routinely break mkinitramfs (“No space left on device”).
WORK_ROOT="${WENDY_WORK:-${TMPDIR:-/tmp}/wendy-iso.${RELEASE}.${ARCH}.$$}"

ROOTFS="${WORK_ROOT}/rootfs"
ISO_STAGE="${WORK_ROOT}/iso"
BOOT_WORK="${WORK_ROOT}/boot"
INITRD_WORK="${WORK_ROOT}/initrd-work"
OUT_ISO="${REPO_ROOT}/wendy.iso"
OUT_PXE="${REPO_ROOT}/pxe"

log() { printf '%s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
	die "run as root: sudo bash build/scripts/build_iso.sh"
fi

for cmd in debootstrap xorriso mksquashfs grub-mkrescue; do
	command -v "$cmd" >/dev/null || die "missing host command: ${cmd}"
done

umask 022
rm -rf "${WORK_ROOT}"
mkdir -p "${ROOTFS}" "${ISO_STAGE}" "${BOOT_WORK}" "${INITRD_WORK}"

log "Work dir: ${WORK_ROOT}"
log "[1/8] debootstrap (${RELEASE}/${ARCH})"
DEB_MIRROR="${DEBIAN_MIRROR:-http://archive.ubuntu.com/ubuntu/}"
debootstrap_opts=(--variant=minbase --merged-usr "--arch=${ARCH}")
debootstrap "${debootstrap_opts[@]}" "${RELEASE}" "${ROOTFS}" "${DEB_MIRROR}"

mkdir -p "${ROOTFS}"/usr/share/wendy-runtime
rm -rf "${ROOTFS}/usr/share/wendy-runtime"/*
cp -a "${WENDY_RT_SRC}/." "${ROOTFS}/usr/share/wendy-runtime/"
chmod +x "${ROOTFS}/usr/share/wendy-runtime/bin/wendy"

install -d "${ROOTFS}/etc/initramfs-tools/hooks"
cat >"${ROOTFS}/etc/initramfs-tools/hooks/wendy-copy-runtime" <<'HOOK'
#!/bin/sh
PREREQ=""
prereqs() { echo "${PREREQ}"; }

case "${1:-}" in
	prereqs) prereqs; exit 0;;
esac

. /usr/share/initramfs-tools/hook-functions

DEST="${DESTDIR}/wendy-runtime"
mkdir -p "${DEST}"
if [ -d /usr/share/wendy-runtime ]; then
	cp -a /usr/share/wendy-runtime/. "${DEST}/"
fi
chmod -R +rX "${DEST}" 2>/dev/null || true
[ -f "${DEST}/bin/wendy" ] && chmod +x "${DEST}/bin/wendy" 2>/dev/null || true
HOOK
chmod +x "${ROOTFS}/etc/initramfs-tools/hooks/wendy-copy-runtime"

cleanup_mounts() {
	if mountpoint -q "${ROOTFS}/dev/pts"; then umount "${ROOTFS}/dev/pts" || true; fi
	if mountpoint -q "${ROOTFS}/dev"; then umount "${ROOTFS}/dev" || true; fi
	if mountpoint -q "${ROOTFS}/sys"; then umount "${ROOTFS}/sys" || true; fi
	if mountpoint -q "${ROOTFS}/proc"; then umount "${ROOTFS}/proc" || true; fi
}
trap cleanup_mounts EXIT

cat >"${ROOTFS}/etc/apt/sources.list" <<EOF
deb http://archive.ubuntu.com/ubuntu ${RELEASE} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${RELEASE}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${RELEASE}-security main restricted universe multiverse
EOF

chroot_pkg_install() {
	mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
	mountpoint -q "${ROOTFS}/sys" || mount -t sysfs sys "${ROOTFS}/sys"
	mountpoint -q "${ROOTFS}/dev" || mount --bind /dev "${ROOTFS}/dev"
	mountpoint -q "${ROOTFS}/dev/pts" || mount -t devpts -o newinstance,ptmxmode=0666 devpts "${ROOTFS}/dev/pts" 2>/dev/null || mount -t devpts devpts "${ROOTFS}/dev/pts"
	chroot "${ROOTFS}" /bin/bash <<'CHROOT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates systemd-sysv systemd \
	linux-image-generic grub-efi-amd64-signed shim-signed casper busybox network-manager initramfs-tools \
	squashfs-tools os-prober dbus

if [[ $(dpkg --print-architecture) == amd64 ]]; then
	apt-get install -y --no-install-recommends grub-pc-bin grub-efi-amd64-bin || true
fi

KV="$(ls /lib/modules 2>/dev/null | sort -V | tail -1 || true)"
[[ -n "${KV}" ]] || { echo >&2 'no Linux kernel modules in chroot'; exit 1; }
update-initramfs -c -k "${KV}"

CHROOT
}

log "[2/8] apt + kernel + initrd hook (inside chroot)"
chroot_pkg_install

log "[3/8] locating kernel artefacts"
unset DEBIAN_FRONTEND

KERNEL_IMAGE=""
if compgen -G "${ROOTFS}/boot/vmlinuz-*generic" >/dev/null; then
	KERNEL_IMAGE="$(basename "$(ls "${ROOTFS}"/boot/vmlinuz-*generic | sort -V | tail -1)")"
elif compgen -G "${ROOTFS}/boot/vmlinuz-*" >/dev/null; then
	KERNEL_IMAGE="$(basename "$(ls "${ROOTFS}"/boot/vmlinuz-* | sort -V | tail -1)")"
fi
[[ -n "${KERNEL_IMAGE}" ]] || die "could not locate vmlinuz in chroot"

log "[4/8] staging casper payloads (kernel + squashfs)"
mkdir -p "${ISO_STAGE}/casper" "${ISO_STAGE}/boot" "${ISO_STAGE}/boot/grub"

install -Dm644 "${ROOTFS}/boot/${KERNEL_IMAGE}" "${ISO_STAGE}/casper/${KERNEL_IMAGE}"

KERNEL_VER="${KERNEL_IMAGE#vmlinuz-}"
INITRD_REAL="${ROOTFS}/boot/initrd.img-${KERNEL_VER}"
if [[ ! -f "${INITRD_REAL}" ]]; then
	mapfile -t _initrds < <(find "${ROOTFS}/boot" -maxdepth 1 -name 'initrd.img-*' -type f | sort -V)
	((${#_initrds[@]})) || die "could not locate initrd in chroot boot/"
	INITRD_REAL="${_initrds[-1]}"
fi
[[ -f "${INITRD_REAL}" ]] || die "could not locate initrd in chroot boot/"
install -Dm644 "${INITRD_REAL}" "${ISO_STAGE}/casper/initrd-wendy.img"
install -Dm644 "${ROOTFS}/boot/${KERNEL_IMAGE}" "${ISO_STAGE}/boot/${KERNEL_IMAGE}"
install -Dm644 "${ISO_STAGE}/casper/initrd-wendy.img" "${ISO_STAGE}/boot/initrd-wendy.img"

if ! mksquashfs "${ROOTFS}" "${ISO_STAGE}/casper/filesystem.squashfs" \
	-comp xz -processors "$(nproc 2>/dev/null || echo 4)" \
	-e proc -e sys -e dev -e run -e tmp -e boot/grub ; then
	mksquashfs "${ROOTFS}" "${ISO_STAGE}/casper/filesystem.squashfs" -comp xz \
		-e proc -e sys -e dev -e run -e tmp -e boot/grub
fi

log "[5/8] shim + grub assets for removable media"

find_shim() {
	local cand
	shopt -s nullglob
	for cand in \
		"${ROOTFS}/usr/lib/shim/shimx64.efi.dualsigned" \
		"${ROOTFS}/usr/lib/shim/shimx64.efi.signed.latest" \
		"${ROOTFS}/usr/lib/shim/"shimx64.efi*.signed*
	do
		[[ -f "${cand}" ]] && printf '%s' "${cand}" && return 0
	done
	while IFS= read -r cand; do
		[[ -f "${cand}" ]] && printf '%s' "${cand}" && return 0
	done < <(find "${ROOTFS}/usr/lib/shim" -maxdepth 1 -name '*.efi*' -type f 2>/dev/null | sort)

	die "cannot find shimx64.efi under ${ROOTFS}/usr/lib/shim — install shim-signed inside chroot"
}

find_grubx64() {
	local cand paths=(
		"${ROOTFS}/boot/efi/EFI/ubuntu/grubx64.efi"
		"${ROOTFS}/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
		"${ROOTFS}/usr/lib/shim/grubx64.efi"
	)
	for cand in "${paths[@]}"; do
		[[ -f "${cand}" ]] && printf '%s' "${cand}" && return 0
	done
	while IFS= read -r cand; do
		[[ -f "${cand}" ]] && printf '%s' "${cand}" && return 0
	done < <(find "${ROOTFS}/boot/efi/EFI" -name grubx64.efi -type f 2>/dev/null | head -1)

	local found
	found="$(find "${ROOTFS}/usr/lib/grub" -name 'grubx64*.efi*' -type f 2>/dev/null | head -1)"
	[[ -n "${found}" && -f "${found}" ]] || die "cannot find grubx64.efi in chroot (install grub-efi-amd64-signed)"
	printf '%s' "${found}"
}

SHIM_EFI="$(find_shim)"
GRUBX64="$(find_grubx64)"

install -Dm644 "${SHIM_EFI}" "${ISO_STAGE}/EFI/BOOT/BOOTX64.EFI"
install -Dm644 "${GRUBX64}" "${ISO_STAGE}/EFI/BOOT/grubx64.efi"
install -Dm644 "${SHIM_EFI}" "${BOOT_WORK}/shimx64.efi"
install -Dm644 "${GRUBX64}" "${BOOT_WORK}/grubx64.efi"

log "[6/8] grub.cfg (+ optional theme)"
mkdir -p "${ISO_STAGE}/boot/grub/themes/wendy"
if [[ -d "${BUILD_TOP}/branding/grub-theme" ]]; then
	cp -a "${BUILD_TOP}/branding/grub-theme/." "${ISO_STAGE}/boot/grub/themes/wendy/" 2>/dev/null || true
fi

K_FILE="/casper/${KERNEL_IMAGE}"

cat >"${ISO_STAGE}/boot/grub/grub.cfg" <<-GRUB
	set timeout=10
	set default=0
	
	terminal_output gfxterm
	loadfont \$prefix/fonts/unicode.pf2 2>/dev/null || true
	
	if [ -s \$prefix/themes/wendy/theme.txt ]; then
	  insmod gfxmenu
	  set theme=\$prefix/themes/wendy/theme.txt
	fi
	
	menuentry "WENDY — Windows Evaluation using Neural Diagnostics for You" {
	    linux ${K_FILE} boot=casper noprompt splash quiet ---
	    initrd /casper/initrd-wendy.img
	}
GRUB

grub-editenv "${ISO_STAGE}/boot/grub/grubenv" create 2>/dev/null || true

log "[7/8] building hybrid ISO (${OUT_ISO})"
rm -f "${OUT_ISO}"
if command -v grub-mkrescue >/dev/null; then
	# grub-mkrescue invokes xorriso for El Torito + EFI + optional BIOS boot.
	xorriso -version >/dev/null 2>&1 || die "grub-mkrescue needs xorriso installed"
	grub-mkrescue \
		--compress=xz \
		-output "${OUT_ISO}" \
		"${ISO_STAGE}"
else
	die "need grub-mkrescue from grub-pc-bin / grub-common for hybrid ISO packaging"
fi

log "[8/8] PXE staging (${OUT_PXE})"
mkdir -p "${OUT_PXE}"
install -Dm644 "${ISO_STAGE}/casper/${KERNEL_IMAGE}" "${OUT_PXE}/vmlinuz"
install -Dm644 "${ISO_STAGE}/casper/initrd-wendy.img" "${OUT_PXE}/initrd-wendy.img"
install -Dm644 "${BOOT_WORK}/shimx64.efi" "${OUT_PXE}/shimx64.efi"
install -Dm644 "${BOOT_WORK}/grubx64.efi" "${OUT_PXE}/grubx64.efi"


log "Done: ${OUT_ISO}"
ls -lah "${OUT_ISO}" "${OUT_PXE}"

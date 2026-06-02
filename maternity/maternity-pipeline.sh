#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════
# M.A.R.T.I.N. — Maternity Ward: Golden Image Pipeline
# ════════════════════════════════════════════════════════════
# Builds a Windows golden image VM with QEMU/libvirt,
# provides VNC access for in-situ configuration,
# runs freshness assessment, syspreps, captures, and
# pushes to FOG (JOG).
# ════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARTIN_DIR="$(dirname "$SCRIPT_DIR")"
MATERNITY_DIR="$SCRIPT_DIR"

# ── Config ──────────────────────────────────────────────────────────────
VM_NAME="${VM_NAME:-Win10-Golden}"
RAM="${RAM:-4096}"
CPUS="${CPUS:-2}"
DISK_GB="${DISK_GB:-64}"
STORAGE_POOL="${STORAGE_POOL:-maternity}"
VNC_PORT="${VNC_PORT:-5901}"
OS_VARIANT="${OS_VARIANT:-win10}"
FRESHNESS_TRACKER="${FRESHNESS_TRACKER:-$MATERNITY_DIR/freshness-tracker}"
FRESHNESS_PS1="${FRESHNESS_PS1:-$MATERNITY_DIR/freshness.ps1}"
FOG_SERVER="${FOG_SERVER:-192.168.88.22}"
FOG_USER="${FOG_USER:-fog}"
FOG_SSH_KEY="${FOG_SSH_KEY:-}"
IMAGE_CAPTURE_DIR="${IMAGE_CAPTURE_DIR:-/var/lib/maternity/captures}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

usage() {
    cat <<EOF
Maternity Ward — Golden Image Pipeline

Usage: $0 <command> [options]

Commands:
  init                    Create storage pool and directories
  create <windows.iso> [drivers.iso]   Create the golden image VM
  start                   Start VM (VNC on port $VNC_PORT)
  vnc                     Show VNC connection info
  inject-freshness        Inject and run freshness.ps1 in the VM
  sysprep                 Run Sysprep inside the VM
  capture <image_name>    Capture the disk image post-sysprep
  upload <image_name>     Upload captured image to FOG server
  full <image_name>       Full pipeline: create → start → wait → capture → upload
  list                    List captured images
  status                  Show VM status

Examples:
  $0 init
  $0 create /iso/Win10_22H2.iso /iso/Win10_drivers.iso
  $0 full Latitude_5420_2026-Q2
EOF
    exit 0
}

[ $# -lt 1 ] && usage
CMD="$1"
shift

ensure_libvirt() {
    if ! virsh list --all &>/dev/null; then
        fail "libvirtd not running. Try: sudo systemctl start libvirtd"
    fi
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "This command requires root. Run with sudo."
    fi
}

# ── init ────────────────────────────────────────────────────────────────
do_init() {
    ensure_root
    info "Initializing Maternity storage..."

    mkdir -p "$IMAGE_CAPTURE_DIR"
    mkdir -p /var/lib/libvirt/images/maternity

    if ! virsh pool-info "$STORAGE_POOL" &>/dev/null; then
        virsh pool-define-as "$STORAGE_POOL" dir --target /var/lib/libvirt/images/maternity
        virsh pool-build "$STORAGE_POOL"
        virsh pool-start "$STORAGE_POOL"
        virsh pool-autostart "$STORAGE_POOL"
        ok "Storage pool '$STORAGE_POOL' created"
    else
        ok "Storage pool '$STORAGE_POOL' already exists"
    fi

    # Ensure default network is active
    if virsh net-info default 2>/dev/null | grep -q 'Active:.*no'; then
        virsh net-start default
        ok "Default network started"
    fi

    # Initialize freshness tracker DB
    if command -v "$FRESHNESS_TRACKER" &>/dev/null; then
        "$FRESHNESS_TRACKER" list &>/dev/null || true
        ok "Freshness tracker initialized"
    fi

    ok "Maternity ward ready"
}

# ── create ──────────────────────────────────────────────────────────────
do_create() {
    ensure_root
    local WIN_ISO="$1"
    local DRV_ISO="${2:-}"

    [ -f "$WIN_ISO" ] || fail "Windows ISO not found: $WIN_ISO"
    [ -n "$DRV_ISO" ] && [ ! -f "$DRV_ISO" ] && warn "Drivers ISO not found: $DRV_ISO (continuing without)"

    if virsh dominfo "$VM_NAME" &>/dev/null; then
        fail "VM '$VM_NAME' already exists. Remove it first: virsh undefine $VM_NAME --nvram"
    fi

    info "Creating golden image VM: $VM_NAME"
    info "  RAM: ${RAM}MB, CPUs: $CPUS, Disk: ${DISK_GB}GB"
    info "  VNC will be available on port $VNC_PORT after start"

    local DISK_PATH="/var/lib/libvirt/images/maternity/${VM_NAME}.qcow2"
    local INSTALL_OPTS=()

    if [ -n "$DRV_ISO" ]; then
        INSTALL_OPTS+=(--disk "$DRV_ISO,device=cdrom,bus=sata")
    fi

    virt-install \
        --name "$VM_NAME" \
        --ram "$RAM" \
        --vcpus "$CPUS" \
        --disk path="$DISK_PATH",format=qcow2,size="$DISK_GB",bus=virtio \
        --cdrom "$WIN_ISO" \
        --os-variant "$OS_VARIANT" \
        --graphics vnc,listen=0.0.0.0,port="$VNC_PORT" \
        --video qxl \
        --network network=default,model=virtio \
        --channel spicevmc \
        --noautoconsole \
        "${INSTALL_OPTS[@]}"

    ok "VM '$VM_NAME' created"
    info "Start it with: $0 start"
    info "Connect via VNC: vncviewer 192.168.88.99:$VNC_PORT"
}

# ── start ───────────────────────────────────────────────────────────────
do_start() {
    ensure_root
    if virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; then
        warn "VM '$VM_NAME' is already running"
    else
        virsh start "$VM_NAME"
        ok "VM '$VM_NAME' started"
    fi
    do_vnc
}

# ── vnc ────────────────────────────────────────────────────────────────
do_vnc() {
    local ACTUAL_PORT
    ACTUAL_PORT=$(virsh domdisplay "$VM_NAME" 2>/dev/null || echo ":$VNC_PORT")
    local IP="${VM_HOST:-192.168.88.99}"
    info "───────────────────────────────────────────"
    info "  VNC Connection:  vncviewer ${IP}${ACTUAL_PORT}"
    info "───────────────────────────────────────────"
}

# ── inject-freshness ──────────────────────────────────────────────────
do_inject_freshness() {
    ensure_root
    local IMAGE_NAME="${1:-$VM_NAME}"
    local ISO_OUT="/tmp/freshness-${VM_NAME}.iso"

    [ -f "$FRESHNESS_PS1" ] || fail "freshness.ps1 not found at $FRESHNESS_PS1"

    local SCRIPT_DIR="/Freshness"
    local TMPDIR="/tmp/freshness-iso-$$"
    mkdir -p "$TMPDIR/$SCRIPT_DIR"

    cp "$FRESHNESS_PS1" "$TMPDIR/$SCRIPT_DIR/"
    cat > "$TMPDIR/$SCRIPT_DIR/run-freshness.cmd" << 'EOF'
@echo off
echo M.A.R.T.I.N. Freshness Assessment
echo =================================
echo.
echo This will run the freshness assessment on this golden image.
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0freshness.ps1" -ImageName "%1"
echo.
echo Assessment complete. Check C:\BitzNBobz\freshness\
pause
EOF

    mkdir -p "$TMPDIR/Autorun"
    cat > "$TMPDIR/Autorun/autorun.cmd" << 'EOF'
@echo off
echo.
echo M.A.R.T.I.N. Maternity Ward - Freshness Injection ISO mounted
echo.
echo To run freshness assessment manually:
echo   C:
echo   cd \Freshness
echo   run-freshness.cmd <ImageName>
echo.
EOF

    genisoimage -o "$ISO_OUT" -R -J "$TMPDIR" 2>/dev/null
    rm -rf "$TMPDIR"

    # Attach the ISO to the VM
    virsh change-media "$VM_NAME" sda --eject 2>/dev/null || true
    virsh attach-disk "$VM_NAME" "$ISO_OUT" sdb --type cdrom --mode readonly 2>/dev/null
    ok "Freshness ISO attached to $VM_NAME as sdb"
    info "Inside the VM, browse D:\Freshness\ and run: run-freshness.cmd $IMAGE_NAME"
    info "Or manually: powershell -ExecutionPolicy Bypass D:\Freshness\freshness.ps1 -ImageName $IMAGE_NAME"
}

# ── sysprep ────────────────────────────────────────────────────────────
do_sysprep() {
    ensure_root
    local OEM_ANSWER_FILE="${1:-}"

    if [ -n "$OEM_ANSWER_FILE" ] && [ -f "$OEM_ANSWER_FILE" ]; then
        local ISO_OUT="/tmp/sysprep-${VM_NAME}.iso"
        local TMPDIR="/tmp/sysprep-iso-$$"
        mkdir -p "$TMPDIR"

        cp "$OEM_ANSWER_FILE" "$TMPDIR/autounattend.xml"
        genisoimage -o "$ISO_OUT" -R -J "$TMPDIR" 2>/dev/null
        rm -rf "$TMPDIR"

        virsh change-media "$VM_NAME" sda --eject 2>/dev/null || true
        virsh attach-disk "$VM_NAME" "$ISO_OUT" sda --type cdrom --mode readonly 2>/dev/null
        ok "Sysprep answer file attached, reboot VM to trigger sysprep"
    else
        warn "No answer file provided. Inside the VM, run manually:"
        info "  C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown"
        info "After shutdown, proceed with: $0 capture <image_name>"
    fi
}

# ── capture ────────────────────────────────────────────────────────────
do_capture() {
    ensure_root
    local IMAGE_NAME="${1:-$VM_NAME}"

    mkdir -p "$IMAGE_CAPTURE_DIR"

    local DISK_PATH="/var/lib/libvirt/images/maternity/${VM_NAME}.qcow2"
    [ -f "$DISK_PATH" ] || fail "VM disk not found: $DISK_PATH"

    # Ensure VM is shut down
    local STATE
    STATE=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "shut off")
    if [ "$STATE" = "running" ]; then
        warn "VM is running. Shutting down..."
        virsh shutdown "$VM_NAME"
        sleep 10
        virsh destroy "$VM_NAME" 2>/dev/null || true
    fi

    local CAPTURE_PATH="$IMAGE_CAPTURE_DIR/${IMAGE_NAME}.qcow2"
    info "Capturing disk image to $CAPTURE_PATH ..."

    # Create a compressed copy
    qemu-img convert -O qcow2 -c "$DISK_PATH" "$CAPTURE_PATH"

    local SIZE
    SIZE=$(du -h "$CAPTURE_PATH" | cut -f1)
    local ORIG_SIZE
    ORIG_SIZE=$(du -h "$DISK_PATH" | cut -f1)
    ok "Image captured: $CAPTURE_PATH ($SIZE, compressed from $ORIG_SIZE)"

    # Generate SHA256
    sha256sum "$CAPTURE_PATH" > "${CAPTURE_PATH}.sha256"
    ok "SHA256: $(cat "${CAPTURE_PATH}.sha256")"

    # Create metadata
    cat > "${CAPTURE_PATH}.meta" << 'META'
{
    "image_name": "$IMAGE_NAME",
    "source_vm": "$VM_NAME",
    "captured_at": "$(date -Iseconds)",
    "compression": "qcow2",
    "original_size": "$ORIG_SIZE",
    "captured_size": "$SIZE"
}
META

    echo "---"
    info "To upload to FOG: $0 upload $IMAGE_NAME"
}

# ── upload ──────────────────────────────────────────────────────────────
do_upload() {
    local IMAGE_NAME="${1:-}"
    [ -n "$IMAGE_NAME" ] || fail "Usage: $0 upload <image_name>"
    local CAPTURE_PATH="$IMAGE_CAPTURE_DIR/${IMAGE_NAME}.qcow2"
    [ -f "$CAPTURE_PATH" ] || fail "Captured image not found: $CAPTURE_PATH"

    info "Uploading $IMAGE_NAME to FOG server ($FOG_SERVER)..."

    # For FOG, we typically need to:
    # 1. SCP the image to the FOG server's image storage
    # 2. Register it in FOG's database (via FOG API or manual)

    if [ -n "$FOG_SSH_KEY" ]; then
        scp -i "$FOG_SSH_KEY" "$CAPTURE_PATH" "${FOG_USER}@${FOG_SERVER}:/images/${IMAGE_NAME}/"
    else
        warn "No FOG SSH key configured. Manual steps required:"
        info "  scp $CAPTURE_PATH ${FOG_USER}@${FOG_SERVER}:/images/${IMAGE_NAME}/"
        info "Then register the image in FOG web UI."
    fi

    ok "Upload complete (or instructions provided)"
}

# ── list ────────────────────────────────────────────────────────────────
do_list() {
    echo "Captured images in $IMAGE_CAPTURE_DIR:"
    echo ""
    if [ -d "$IMAGE_CAPTURE_DIR" ]; then
        ls -lh "$IMAGE_CAPTURE_DIR"/*.qcow2 2>/dev/null || echo "(none)"
    else
        echo "(directory not yet created)"
    fi

    echo ""
    echo "Freshness reports:"
    if command -v "$FRESHNESS_TRACKER" &>/dev/null; then
        "$FRESHNESS_TRACKER" list
    else
        echo "(freshness tracker not configured)"
    fi
}

# ── status ─────────────────────────────────────────────────────────────
do_status() {
    if virsh dominfo "$VM_NAME" &>/dev/null; then
        virsh dominfo "$VM_NAME"
    else
        warn "VM '$VM_NAME' does not exist"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────
case "$CMD" in
    init)               do_init "$@" ;;
    create)             do_create "$@" ;;
    start)              do_start ;;
    vnc)                do_vnc ;;
    inject-freshness)   do_inject_freshness "$@" ;;
    sysprep)            do_sysprep "$@" ;;
    capture)            do_capture "$@" ;;
    upload)             do_upload "$@" ;;
    list)               do_list ;;
    status)             do_status ;;
    full)
        local IMAGE_NAME="${1:-}"
        [ -n "$IMAGE_NAME" ] || fail "Usage: $0 full <image_name>"
        warn "Full pipeline: skipping create step (run 'create' first)"
        warn "After you finish configuring the VM, run:"
        info "  $0 inject-freshness $IMAGE_NAME"
        info "  # Inside VM: run freshness.ps1"
        info "  # Inside VM: run sysprep /generalize /oobe /shutdown"
        info "  $0 capture $IMAGE_NAME"
        info "  $0 upload $IMAGE_NAME"
        ;;
    help|--help|-h)     usage ;;
    *)                  fail "Unknown command: $CMD (use --help)" ;;
esac

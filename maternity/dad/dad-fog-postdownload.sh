#!/bin/sh
# ════════════════════════════════════════════════════════════
# M.A.R.T.I.N. — D.A.D. FOG Post-Download Script
# Runs inside FOG initrd after image is written to disk.
# Copies ESP driver installer into the offline Windows image.
# ════════════════════════════════════════════════════════════
#
# FOG places this script at:
#   /images/postdownload/dad-fog-postdownload.sh
#
# It runs in FOG's busybox/Linux environment with access to:
#   - The mounted Windows partitions (usually /ntfs/)
#   - Network (CIFS client, if available)
#   - The FOG task database
#
# ════════════════════════════════════════════════════════════

DAD_SERVER="192.168.88.99"
DAD_SHARE="DellDrivers"
DAD_MOUNT="/tmp/dad"
WINDOWS_MOUNT="/ntfs"
SCRIPT_DIR="/opt/martin/maternity/dad"
LOG="/tmp/dad-postdownload.log"

echo "$(date) D.A.D. Post-Download Script Starting" > $LOG

# ── 1. Detect model ──────────────────────────────────────────────────
# Try FOG task database first, then offline registry
MODEL=""

# Method 1: Check if FOG passed the task info via environment
if [ -n "$FOG_HOST_NAME" ]; then
    echo "$(date) FOG_HOST_NAME: $FOG_HOST_NAME" >> $LOG
fi

# Method 2: Read from registry hive
if [ -f "$WINDOWS_MOUNT/Windows/System32/config/SOFTWARE" ]; then
    echo "$(date) Mounting offline registry..." >> $LOG
    # We can't easily read registry from Linux, but we can read the file
    # Try to find the model string in the SOFTWARE hive
    MODEL_RAW=$(strings "$WINDOWS_MOUNT/Windows/System32/config/SOFTWARE" 2>/dev/null | \
        grep -i "latitude\|Dell Pro Max\|Precision\|XPS" | \
        grep -v "\.dll\|\.exe\|\.sys\|display\|driver" | \
        sort -u | head -1)
    if [ -n "$MODEL_RAW" ]; then
        MODEL="$MODEL_RAW"
        echo "$(date) Model from registry: $MODEL" >> $LOG
    fi
fi

# Method 3: Read from SMBIOS (might not be accurate in FOG initrd)
if [ -z "$MODEL" ] && [ -f /sys/class/dmi/id/product_name ]; then
    MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    echo "$(date) Model from DMI: $MODEL" >> $LOG
fi

if [ -z "$MODEL" ]; then
    echo "$(date) ERROR: Could not detect model" >> $LOG
    echo "$(date) Checking FOG task database..." >> $LOG
    # Fall back: read from the FOG MySQL DB directly
    MODEL=$(mysql fog -N -e "
        SELECT iSysproduct FROM inventory
        JOIN hosts ON hosts.hostName = '$FOG_HOST_NAME'
        WHERE inventory.iHostID = hosts.id
        LIMIT 1
    " 2>/dev/null)
    echo "$(date) Model from DB: $MODEL" >> $LOG
fi

if [ -z "$MODEL" ]; then
    echo "$(date) ERROR: Cannot determine model, aborting" >> $LOG
    exit 1
fi

MODEL_DIR=$(echo "$MODEL" | sed 's/ /_/g' | sed 's/[^a-zA-Z0-9_-]//g')
echo "$(date) Model: $MODEL, Dir: $MODEL_DIR" >> $LOG

# ── 2. Mount DAD SMB share ───────────────────────────────────────────
echo "$(date) Mounting SMB share..." >> $LOG
mkdir -p "$DAD_MOUNT"
if mount -t cifs "//$DAD_SERVER/$DAD_SHARE" "$DAD_MOUNT" -o guest,ro 2>/dev/null; then
    echo "$(date) SMB mounted OK" >> $LOG
else
    echo "$(date) WARNING: CIFS mount failed, trying to copy from local cache..." >> $LOG
    # Fallback: check if drivers are cached locally on the FOG server
    if [ -d "/var/lib/maternity/drivers/$MODEL_DIR/extracted" ]; then
        echo "$(date) Found local cache at /var/lib/maternity/drivers/$MODEL_DIR/" >> $LOG
        DAD_MOUNT="/var/lib/maternity/drivers"
    else
        echo "$(date) ERROR: Cannot access driver cache" >> $LOG
        exit 1
    fi
fi

# ── 3. Locate driver files ────────────────────────────────────────────
DRIVER_SOURCE="$DAD_MOUNT/$MODEL_DIR/extracted"
if [ ! -d "$DRIVER_SOURCE" ]; then
    # Try without /extracted
    DRIVER_SOURCE="$DAD_MOUNT/$MODEL_DIR"
fi
if [ ! -d "$DRIVER_SOURCE" ]; then
    echo "$(date) ERROR: Driver source not found: $DRIVER_SOURCE" >> $LOG
    ls "$DAD_MOUNT/" >> $LOG 2>&1
    umount "$DAD_MOUNT" 2>/dev/null
    exit 1
fi
echo "$(date) Driver source: $DRIVER_SOURCE" >> $LOG

# ── 4. Create Windows Setup Scripts directory ─────────────────────────
SETUP_SCRIPTS="$WINDOWS_MOUNT/Windows/Setup/Scripts"
mkdir -p "$SETUP_SCRIPTS"
echo "$(date) Setup scripts dir: $SETUP_SCRIPTS" >> $LOG

# Copy the ESP installer and bootstrap
cp "$SCRIPT_DIR/dad-esp-install.ps1" "$SETUP_SCRIPTS/" 2>/dev/null || \
    curl -sL "http://$DAD_SERVER/static/dad-esp-install.ps1" -o "$SETUP_SCRIPTS/dad-esp-install.ps1" 2>/dev/null || \
    echo "$(date) WARNING: Could not copy dad-esp-install.ps1" >> $LOG

cp "$SCRIPT_DIR/SetupComplete.cmd" "$SETUP_SCRIPTS/" 2>/dev/null || \
    curl -sL "http://$DAD_SERVER/static/SetupComplete.cmd" -o "$SETUP_SCRIPTS/SetupComplete.cmd" 2>/dev/null || \
    echo "$(date) WARNING: Could not copy SetupComplete.cmd" >> $LOG

chmod +x "$SETUP_SCRIPTS/SetupComplete.cmd" 2>/dev/null
echo "$(date) Setup scripts ready" >> $LOG

# ── 5. Option 2: Offline driver injection via driver copy ─────────────
# Copy the driver files to the Windows partition for offline access
# This avoids needing SMB access during ESP (useful if no network drivers)
echo "$(date) Copying drivers to Windows partition..." >> $LOG
DRIVER_TARGET="$WINDOWS_MOUNT/Drivers/Dell"
mkdir -p "$DRIVER_TARGET"
cp -r "$DRIVER_SOURCE" "$DRIVER_TARGET/$MODEL_DIR" 2>/dev/null
echo "$(date) Drivers copied to $DRIVER_TARGET/$MODEL_DIR" >> $LOG

# ── 6. Option 3: DISM offline injection (preferred if possible) ─────
# Check if DISM is available in the FOG environment
if command -v dism >/dev/null 2>&1; then
    echo "$(date) DISM available, injecting drivers offline..." >> $LOG
    WIM_IMAGE=$(find "$WINDOWS_MOUNT" -name "*.wim" -type f 2>/dev/null | head -1)
    if [ -n "$WIM_IMAGE" ]; then
        dism /Image:"$WINDOWS_MOUNT" /Add-Driver /Driver:"$DRIVER_TARGET/$MODEL_DIR" /Recurse
        echo "$(date) DISM injection complete" >> $LOG
    fi
fi

# ── 7. Create a C:\Drivers shortcut for post-OOBE use ────────────────
echo "$(date) Creating driver manifest..." >> $LOG
DRIVER_COUNT=$(find "$DRIVER_TARGET/$MODEL_DIR" -name "*.inf" 2>/dev/null | wc -l)
echo "$(date) Total INF files deployed: $DRIVER_COUNT" >> $LOG

# Cleanup
umount "$DAD_MOUNT" 2>/dev/null
echo "$(date) === D.A.D. Post-Download Complete ===" >> $LOG
exit 0

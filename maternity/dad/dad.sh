#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
# M.A.R.T.I.N. — D.A.D. (Driver Availability Directory)
# Scans FOG inventory for device models, maintains an offline
# Dell driver cache, and serves drivers to newly imaged devices.
# ════════════════════════════════════════════════════════════
# Usage:
#   dad.sh scan         # Query FOG DB for models, compare cache
#   dad.sh status       # Show cache status per model
#   dad.sh serve        # Ensure SMB share is configured & running
#   dad.sh manifest     # Generate download manifest (for manual DL)
#   dad.sh register <model> <cab_url>  # Manually add a driver pack
# ════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_ROOT="${DRIVER_ROOT:-/var/lib/maternity/drivers}"
MANIFEST="${DRIVER_ROOT}/.manifest.json"
LOG_DIR="${LOG_DIR:-/var/log/maternity}"
LOG="$LOG_DIR/dad.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "$(date "+%Y-%m-%d %H:%M:%S") $*" | tee -a "$LOG"; }
info()  { log "${CYAN}[INFO]${NC}  $*"; }
ok()    { log "${GREEN}[OK]${NC}    $*"; }
warn()  { log "${YELLOW}[WARN]${NC}  $*"; }
fail()  { log "${RED}[FAIL]${NC}  $*"; }

# ── Scan FOG for Dell models ─────────────────────────────────────────
scan_fog_models() {
    sudo mysql fog -N -e "
        SELECT DISTINCT iSysproduct
        FROM inventory
        WHERE iSysman LIKE '%Dell%'
          AND iSysproduct IS NOT NULL
          AND iSysproduct != ''
        ORDER BY iSysproduct;
    " 2>/dev/null || true
}

# ── Get cache status for a model ─────────────────────────────────────
model_status() {
    local model="$1"
    local dir_name="${model// /_}"
    dir_name="${dir_name//[^a-zA-Z0-9_-]/}"
    local target="$DRIVER_ROOT/$dir_name"
    local manifest="$target/.metadata.json"

    if [ -f "$manifest" ]; then
        local files version url
        files=$(python3 -c "import json; d=json.load(open('$manifest')); print(d.get('files',0))" 2>/dev/null || echo "0")
        version=$(python3 -c "import json; d=json.load(open('$manifest')); print(d.get('version','unknown'))" 2>/dev/null || echo "unknown")
        url=$(python3 -c "import json; d=json.load(open('$manifest')); print(d.get('source',''))" 2>/dev/null || echo "")
        local size
        size=$(du -sh "$target" 2>/dev/null | cut -f1)
        echo "cached|$version|$files|$size|$url"
    else
        echo "missing|||"
    fi
}

# ── Commands ─────────────────────────────────────────────────────────
cmd_scan() {
    mkdir -p "$DRIVER_ROOT" "$LOG_DIR"
    info "Scanning FOG inventory for Dell models..."

    local models
    models=$(scan_fog_models)
    if [ -z "$models" ]; then
        warn "No Dell models found in FOG inventory"
        return 1
    fi

    echo ""
    printf "%-35s %-10s %-8s %-8s %s\n" "MODEL" "STATUS" "FILES" "SIZE" "VERSION"
    printf "%-35s %-10s %-8s %-8s %s\n" "-----" "------" "-----" "----" "-------"

    echo "$models" | while IFS= read -r model; do
        [ -z "$model" ] && continue
        local status
        status=$(model_status "$model")
        local state version files size url
        state=$(echo "$status" | cut -d'|' -f1)
        version=$(echo "$status" | cut -d'|' -f2)
        files=$(echo "$status" | cut -d'|' -f3)
        size=$(echo "$status" | cut -d'|' -f4)
        url=$(echo "$status" | cut -d'|' -f5)

        if [ "$state" = "cached" ]; then
            printf "%-35s %-10s %-8s %-8s %s\n" "$model" "${GREEN}cached${NC}" "$files" "$size" "$version"
        else
            printf "%-35s %-10s %-8s %-8s %s\n" "$model" "${YELLOW}missing${NC}" "-" "-" ""
        fi
    done
}

cmd_status() {
    echo ""
    info "D.A.D. Driver Availability Directory"
    info "Root: $DRIVER_ROOT"
    echo ""

    if [ ! -d "$DRIVER_ROOT" ]; then
        info "Cache directory does not exist yet."
        return
    fi

    local total_models=0
    local cached_models=0
    local total_files=0
    local total_size="0B"

    for d in "$DRIVER_ROOT"/*/; do
        [ -d "$d" ] || continue
        local model
        model=$(basename "$d")
        [[ "$model" == .* ]] && continue
        total_models=$((total_models + 1))

        local meta="$d/.metadata.json"
        if [ -f "$meta" ]; then
            local files
            files=$(python3 -c "import json; print(json.load(open('$meta')).get('files',0))" 2>/dev/null || echo "0")
            total_files=$((total_files + files))
            cached_models=$((cached_models + 1))
        fi
    done

    total_size=$(du -sh "$DRIVER_ROOT" 2>/dev/null | cut -f1)

    printf "%-25s %s\n" "Models in cache:" "$total_models"
    printf "%-25s %s\n" "Cached:" "$cached_models"
    printf "%-25s %s\n" "Total driver files:" "$total_files"
    printf "%-25s %s\n" "Total size:" "$total_size"
    echo ""

    if [ "$total_models" -gt 0 ]; then
        printf "%-35s %-10s %-10s %s\n" "MODEL" "FILES" "SIZE" "VERSION"
        printf "%-35s %-10s %-10s %s\n" "-----" "-----" "----" "-------"
        for d in "$DRIVER_ROOT"/*/; do
            [ -d "$d" ] || continue
            model=$(basename "$d")
            [[ "$model" == .* ]] && continue
            local sfiles="0" ssize="-" sversion="-"
            local meta="$d/.metadata.json"
            if [ -f "$meta" ]; then
                sfiles=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('files',0))" 2>/dev/null || echo "0")
                ssize=$(du -sh "$d" 2>/dev/null | cut -f1)
                sversion=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('version','-'))" 2>/dev/null || echo "-")
            fi
            printf "%-35s %-10s %-10s %s\n" "$model" "$sfiles" "$ssize" "$sversion"
        done
    fi
}

cmd_serve() {
    info "Configuring Samba share..."

    local share_conf="/etc/samba/smb.conf"
    local share_def="
[DellDrivers]
    path = $DRIVER_ROOT
    browseable = yes
    read only = yes
    guest ok = yes
    comment = M.A.R.T.I.N. D.A.D. - Driver Availability Directory
"

    if grep -q "\[DellDrivers\]" "$share_conf" 2>/dev/null; then
        ok "Samba share 'DellDrivers' already configured"
    else
        echo "$share_def" >> "$share_conf"
        ok "Added 'DellDrivers' share to Samba"
    fi

    systemctl enable smbd 2>/dev/null || true
    systemctl restart smbd 2>/dev/null || true

    smbclient -L 127.0.0.1 -N 2>&1 | grep -q "DellDrivers" \
        && ok "Samba share active at \\\\$(hostname -I | awk '{print $1}')\\DellDrivers" \
        || warn "Samba share not detected"
}

cmd_manifest() {
    mkdir -p "$DRIVER_ROOT"
    info "Generating download manifest for missing drivers..."

    local models
    models=$(scan_fog_models)
    if [ -z "$models" ]; then
        warn "No models found"
        return 1
    fi

    local manifest_file="$DRIVER_ROOT/download-manifest.txt"
    echo "# D.A.D. Download Manifest — Generated $(date)" > "$manifest_file"
    echo "#" >> "$manifest_file"
    echo "# Download each CAB from Dell Support site and place in:" >> "$manifest_file"
    echo "#   /var/lib/maternity/drivers/<MODEL_DIR>/" >> "$manifest_file"
    echo "# Then run: dad.sh register <model> <cab_filename>" >> "$manifest_file"
    echo "" >> "$manifest_file"

    echo "$models" | while IFS= read -r model; do
        [ -z "$model" ] && continue
        local dir_name="${model// /_}"
        dir_name="${dir_name//[^a-zA-Z0-9_-]/}"
        local target="$DRIVER_ROOT/$dir_name"

        if [ -f "$target/.metadata.json" ]; then
            echo "[CACHED] $model" >> "$manifest_file"
        else
            local encoded
            encoded=$(echo "$model" | sed 's/ /%20/g')
            local url="https://www.dell.com/support/home/en-us/product-support/product/${model,,}/drivers"
            echo "[MISSING] $model" >> "$manifest_file"
            echo "  URL: $url" >> "$manifest_file"
            echo "  Target: $target/" >> "$manifest_file"
            echo "" >> "$manifest_file"
        fi
    done

    ok "Manifest written: $manifest_file"
    cat "$manifest_file"
}

cmd_register() {
    local model="$1"
    local cab_path="$2"

    if [ -z "$model" ] || [ -z "$cab_path" ]; then
        fail "Usage: dad.sh register <model> <cab_file_or_url>"
        exit 1
    fi

    local dir_name="${model// /_}"
    dir_name="${dir_name//[^a-zA-Z0-9_-]/}"
    local target="$DRIVER_ROOT/$dir_name"

    mkdir -p "$target"

    local archive="$target/package.cab"
    if [ -f "$cab_path" ]; then
        info "Processing for $model: $cab_path"
        if [[ "$cab_path" == *.exe ]] || [[ "$cab_path" == *.EXE ]]; then
            cp "$cab_path" "$target/package.exe"
            archive="$target/package.exe"
        else
            cp "$cab_path" "$archive"
        fi
    elif echo "$cab_path" | grep -q "^https\?://"; then
        info "Downloading from $cab_path ..."
        if [[ "$cab_path" == *.exe ]] || [[ "$cab_path" == *.EXE ]]; then
            archive="$target/package.exe"
            curl -sL --connect-timeout 30 --max-time 600 -o "$archive" "$cab_path" || {
                fail "Download failed"; rm -f "$archive"; exit 1
            }
        else
            curl -sL --connect-timeout 30 --max-time 300 -o "$archive" "$cab_path" || {
                fail "Download failed"; rm -f "$archive"; exit 1
            }
        fi
    else
        fail "Not a file or URL: $cab_path"
        exit 1
    fi

    info "Extracting..."
    mkdir -p "$target/extracted"

    local extract_ok=false
    # Try 7z (handles EXE/SFX archives and CABs)
    if 7z x "$archive" -o"$target/extracted" -y -bso0 2>/dev/null; then
        extract_ok=true
    # Fallback: cabextract
    elif cabextract -d "$target/extracted" -q "$archive" 2>/dev/null; then
        extract_ok=true
    fi

    if [ "$extract_ok" = true ]; then
        local file_count
        file_count=$(find "$target/extracted" -type f | wc -l)
        local md5
        md5=$(md5sum "$archive" | cut -d' ' -f1)

        python3 -c "
import json
meta = {
    'model': '$model',
    'version': '$(date +%Y%m%d)',
    'files': $file_count,
    'source': '$cab_path',
    'md5': '$md5',
    'updated': '$(date -Iseconds)'
}
with open('$target/.metadata.json', 'w') as f:
    json.dump(meta, f, indent=2)
" 2>/dev/null

        ok "Registered $model: $file_count driver files"
        rm -f "$archive"
        cmd_gen_catalog
    else
        warn "Extraction failed for $model"
        rm -f "$archive"
        return 1
    fi
}

# ── Known KB articles for Dell driver packs ──────────────────────────
declare -A KB_ARTICLES
KB_ARTICLES["Latitude 3410"]="000197128"
KB_ARTICLES["Latitude 3440"]="000211753"
KB_ARTICLES["Latitude 3450"]="000223150"
KB_ARTICLES["Latitude 3550"]="000223153"
KB_ARTICLES["Dell Pro Max 16 MC16250"]="000301242"

# ── Fetch driver pack URL from Dell KB article ───────────────────────
fetch_driver_url() {
    local model="$1"
    local kb_id="${KB_ARTICLES[$model]:-}"
    if [ -z "$kb_id" ]; then
        echo ""
        return
    fi
    local url_key="${model// /-}"
    url_key="${url_key,,}"
    local kb_url="https://www.dell.com/support/kbdoc/en-us/${kb_id}/${url_key}-windows11-driver-pack"
    python3 -c "
from curl_cffi import requests
import re, sys
try:
    r = requests.get('$kb_url', impersonate='chrome124', timeout=20)
    m = re.search(r'https://downloads\.dell\.com/FOLDER[^\"\\'<>]+', r.text)
    if m: print(m.group(0))
except: pass
" 2>/dev/null || true
}

# ── Download and extract driver pack for a model ─────────────────────
cmd_download() {
    local model="${1:-}"
    if [ -z "$model" ]; then
        # No model specified — download all missing
        local models
        models=$(scan_fog_models)
        if [ -z "$models" ]; then
            fail "No models found in FOG inventory"
            exit 1
        fi
        echo "$models" | while IFS= read -r m; do
            [ -z "$m" ] && continue
            cmd_download "$m"
        done
        return
    fi

    info "Fetching driver URL for: $model"
    local cab_url
    cab_url=$(fetch_driver_url "$model")
    if [ -z "$cab_url" ]; then
        warn "No KB article known for: $model"
        warn "Try: https://www.dell.com/support/kbdoc/en-us/search?keyword=${model// /+}+driver+pack"
        exit 1
    fi
    ok "Found: $cab_url"

    local dir_name="${model// /_}"
    dir_name="${dir_name//[^a-zA-Z0-9_-]/}"
    local target="$DRIVER_ROOT/$dir_name"
    mkdir -p "$target"
    local ext_file="$target/package.exe"

    local expected_mb=3000
    warn "Downloading (~${expected_mb}MB)..."
    curl -L -o "$ext_file" --progress-bar "$cab_url" 2>&1

    local actual_size
    actual_size=$(stat -c%s "$ext_file" 2>/dev/null || echo 0)
    if [ "$actual_size" -lt 50000000 ]; then
        fail "Download too small ($actual_size bytes)"
        rm -f "$ext_file"
        exit 1
    fi
    ok "Downloaded: $((actual_size / 1024 / 1024)) MB"

    info "Extracting with 7z..."
    mkdir -p "$target/extracted"
    if 7z x "$ext_file" -o"$target/extracted" -y -bso0 2>/dev/null; then
        local file_count
        file_count=$(find "$target/extracted" -type f | wc -l)
        ok "Extracted $file_count driver files for $model"

        local cab_md5
        cab_md5=$(md5sum "$ext_file" | cut -d' ' -f1)
        python3 -c "
import json
meta = {
    'model': '$model',
    'version': '$(date +%Y%m%d)',
    'files': $file_count,
    'source': '$cab_url',
    'md5': '$cab_md5',
    'updated': '$(date -Iseconds)'
}
with open('$target/.metadata.json', 'w') as f:
    json.dump(meta, f, indent=2)
" 2>/dev/null
        rm -f "$ext_file"
        cmd_gen_catalog
        ok "Driver cache ready for $model"
    else
        fail "Extraction failed for $model"
        rm -f "$ext_file"
        exit 1
    fi
}


# --- Deploy ESP installer to FOG postdownload --------------------
cmd_deploy() {
    local src="$SCRIPT_DIR/dad-fog-postdownload.sh"
    local dst="/images/postdownload/z-martin-dad.sh"
    mkdir -p /images/postdownload
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "Post-download script deployed: $dst"

    local web_static="/opt/martin/maternity/web/static"
    mkdir -p "$web_static"
    cp "$SCRIPT_DIR/dad-esp-install.ps1" "$web_static/"
    cp "$SCRIPT_DIR/SetupComplete.cmd" "$web_static/"
    ok "ESP installer files deployed to web static"
    echo ""
    info "FOG postdownload will auto-deploy drivers during imaging"
}

cmd_gen_catalog() {
    local catalog="$DRIVER_ROOT/.catalog.json"
    python3 -c "
import json, os

root = '$DRIVER_ROOT'
catalog = {'generated': '$(date -Iseconds)', 'models': {}}

if not os.path.isdir(root):
    pass
else:
    for model in sorted(os.listdir(root)):
        model_dir = os.path.join(root, model)
        if not os.path.isdir(model_dir) or model.startswith('.'):
            continue
        meta_file = os.path.join(model_dir, '.metadata.json')
        meta = {}
        if os.path.exists(meta_file):
            with open(meta_file) as f:
                meta = json.load(f)
        extracted = os.path.join(model_dir, 'extracted')
        categories = {}
        if os.path.isdir(extracted):
            for root_dir, dirs, files in os.walk(extracted):
                rel = os.path.relpath(root_dir, extracted)
                cat = rel.split(os.sep)[0] if rel != '.' else 'root'
                count = categories.get(cat, 0)
                categories[cat] = count + len(files)
        catalog['models'][model] = {
            'meta': meta,
            'categories': categories,
            'total_files': sum(categories.values())
        }

with open('$catalog', 'w') as f:
    json.dump(catalog, f, indent=2)
" 2>/dev/null && ok "Catalog regenerated: $catalog" || warn "Catalog generation failed"
}

# ── Main ──────────────────────────────────────────────────────────────
case "${1:-help}" in
deploy)    cmd_deploy ;;
    scan)      cmd_scan ;;
    status)    cmd_status ;;
    serve)     cmd_serve ;;
    manifest)  cmd_manifest ;;
    download)  shift; cmd_download "$@" ;;
    register)  shift; cmd_register "$@" ;;
    gen-catalog) cmd_gen_catalog ;;
    help|*)
        echo "Usage: $0 {scan|status|serve|manifest|download|register}"
        echo ""
        echo "  scan                  Query FOG inventory, show cache status"
        echo "  status                Show detailed cache status"
        echo "  serve                 Ensure SMB share is running"
        echo "  manifest              Generate download manifest for manual DL"
        echo "  download [model]      Auto-download driver pack from Dell (all missing if no model)"
echo "  deploy                Deploy ESP installer to FOG postdownload scripts"
        echo "  register <m> <cab>    Register a CAB file or URL for a model"
        ;;
esac

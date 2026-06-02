#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════
# M.A.R.T.I.N. — Pharmacy: Dell Driver Cache Manager
# Maintains a read-only Samba share of Dell drivers
# for all models in the fleet.
# ════════════════════════════════════════════════════════════
# Usage:
#   driver-cache.sh update          # Download/extract latest drivers
#   driver-cache.sh status          # Show cache status per model
#   driver-cache.sh verify <model>  # Check a specific model has drivers
#   driver-cache.sh list            # List all cached models
#   driver-cache.sh sync-fog        # Pull model list from FOG database
# ════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_ROOT="${DRIVER_ROOT:-/var/lib/maternity/drivers}"
CACHE_DIR="${CACHE_DIR:-$DRIVER_ROOT/.cache}"
MODELS_CFG="${MODELS_CFG:-$SCRIPT_DIR/models.cfg}"
LOG_DIR="${LOG_DIR:-/var/log/maternity}"
LOCKFILE="/tmp/driver-cache.lock"
DELL_API_BASE="https://www.dell.com/support/api/catalog/v2"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

# ── Setup ──────────────────────────────────────────────────────────────
setup() {
    mkdir -p "$DRIVER_ROOT" "$CACHE_DIR" "$LOG_DIR"

    # Install required tools if missing
    for cmd in curl wget cabextract smbclient; do
        if ! command -v "$cmd" &>/dev/null; then
            info "Installing $cmd..."
            apt-get install -y "$cmd" 2>/dev/null || warn "Cannot install $cmd"
        fi
    done

    # Ensure Samba is available
    if ! command -v smbd &>/dev/null; then
        info "Installing Samba..."
        apt-get install -y samba 2>/dev/null || warn "Cannot install samba"
    fi
}

# ── Read Models Config ─────────────────────────────────────────────────
read_models() {
    if [ -f "$MODELS_CFG" ]; then
        grep -v '^#' "$MODELS_CFG" | grep -v '^$' | while IFS='|' read -r model id os; do
            model=$(echo "$model" | xargs)
            id=$(echo "$id" | xargs)
            os=$(echo "$os" | xargs)
            [ -n "$model" ] && echo "$model|$id|$os"
        done
    elif [ -n "${FOG_DB_MODELS:-}" ]; then
        echo "$FOG_DB_MODELS"
    else
        warn "No models config found at $MODELS_CFG"
        warn "Create one or use: driver-cache.sh sync-fog"
        return 1
    fi
}

# ── Query Dell API for latest driver pack ─────────────────────────────
query_dell_drivers() {
    local model_id="$1"
    local os_code="${2:-W10x64}"
    local api_url="$DELL_API_BASE/Product/$model_id/Category/Driver"

    info "Querying Dell API: $model_id ($os_code)..."

    local response
    response=$(curl -s --connect-timeout 15 "$api_url" 2>/dev/null || echo "")

    if [ -z "$response" ] || echo "$response" | grep -qi 'error\|not found'; then
        warn "Dell API returned no data for $model_id"
        return 1
    fi

    # Extract latest driver CAB download URL
    # Dell API returns JSON with driver details
    local cab_url
    cab_url=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    drivers = data if isinstance(data, list) else data.get('data', [])
    # Pick the latest CAB file for the target OS
    for d in drivers:
        name = d.get('name', '') or d.get('fileName', '') or ''
        oslist = str(d.get('operatingSystems', []) + d.get('supportedOperatingSystems', []))
        if name.lower().endswith('.cab') and ('10' in oslist or '11' in oslist):
            for f in d.get('files', [d]):
                url = f.get('url', '') or f.get('fileUrl', '') or ''
                if url:
                    print(url)
                    sys.exit(0)
    # Fallback: any CAB
    for d in drivers:
        for f in d.get('files', [d]):
            url = f.get('url', '') or f.get('fileUrl', '') or ''
            if url.lower().endswith('.cab'):
                print(url)
                sys.exit(0)
except: pass
" 2>/dev/null || echo "")

    if [ -n "$cab_url" ]; then
        echo "$cab_url"
        return 0
    fi

    # Fallback: try the Dell driver pack CAB URL pattern
    # Dell publishes CABs at predictable paths
    local fallback_url="https://dl.dell.com/FOLDER/CABs/${model_id// /-}-Driver-Pack.CAB"
    if curl -sI "$fallback_url" 2>/dev/null | grep -q '200\|302'; then
        echo "$fallback_url"
        return 0
    fi

    return 1
}

# ── Download & Extract Driver CAB ─────────────────────────────────────
download_and_extract() {
    local model="$1"
    local model_id="$2"
    local os_code="$3"

    local model_dir="$DRIVER_ROOT/$model"
    local cab_path="$CACHE_DIR/${model}.cab"
    local version_file="$model_dir/.version"

    mkdir -p "$model_dir"

    info "  Fetching driver list for $model..."
    local cab_url
    cab_url=$(query_dell_drivers "$model_id" "$os_code" || true)

    if [ -z "$cab_url" ]; then
        warn "  No driver CAB found for $model — skipping"
        return 1
    fi

    info "  Downloading: $cab_url"
    if curl -L -# --connect-timeout 30 --max-time 300 -o "$cab_path" "$cab_url" 2>/dev/null; then
        local size
        size=$(du -h "$cab_path" | cut -f1)
        ok "  Downloaded ${model}.cab ($size)"
    else
        warn "  Download failed for $model"
        rm -f "$cab_path"
        return 1
    fi

    info "  Extracting to $model_dir..."
    mkdir -p "$model_dir"
    if cabextract -d "$model_dir" -q "$cab_path" 2>/dev/null; then
        local file_count
        file_count=$(find "$model_dir" -type f | wc -l)
        local cab_md5
        cab_md5=$(md5sum "$cab_path" | cut -d' ' -f1)
        echo "$cab_md5|$(date -Iseconds)|$file_count files|$cab_url" > "$version_file"
        ok "  $model: $file_count driver files extracted"
        return 0
    else
        warn "  Extraction failed for $model"
        return 1
    fi
}

# ── Update All Models ──────────────────────────────────────────────────
do_update() {
    setup

    if [ -f "$LOCKFILE" ]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "unknown")
        if kill -0 "$pid" 2>/dev/null; then
            fail "Another update is already running (PID $pid)"
            exit 1
        fi
        warn "Stale lockfile removed"
    fi
    echo "$$" > "$LOCKFILE"
    trap 'rm -f "$LOCKFILE"' EXIT

    local start_time
    start_time=$(date +%s)
    local updated=0
    local failed=0
    local skipped=0

    echo ""
    info "╔══════════════════════════════════════════════════════════╗"
    info "║       M.A.R.T.I.N. Pharmacy — Driver Cache Update      ║"
    info "╚══════════════════════════════════════════════════════════╝"
    echo ""

    local models
    models=$(read_models) || { fail "No models to process"; exit 1; }

    echo "$models" | while IFS='|' read -r model id os; do
        [ -z "$model" ] && continue
        echo ""
        info "Processing: $model"

        local model_dir="$DRIVER_ROOT/$model"
        local version_file="$model_dir/.version"

        # Check if we already have the latest
        if [ -f "$version_file" ]; then
            local last_md5
            last_md5=$(cut -d'|' -f1 "$version_file" 2>/dev/null || echo "")
            local last_date
            last_date=$(cut -d'|' -f2 "$version_file" 2>/dev/null || echo "unknown")
            info "  Last updated: $last_date"
        fi

        if download_and_extract "$model" "$id" "$os"; then
            : $((updated++))
        else
            : $((failed++))
        fi
    done

    # Generate catalog index
    generate_catalog

    local elapsed=$(( $(date +%s) - start_time ))
    echo ""
    info "Update complete in ${elapsed}s"
    info "Driver root: $DRIVER_ROOT (used: $(du -sh "$DRIVER_ROOT" 2>/dev/null | cut -f1))"
}

# ── Generate Catalog Index ─────────────────────────────────────────────
generate_catalog() {
    local catalog="$DRIVER_ROOT/.catalog.json"

    info "Generating driver catalog index..."

    python3 -c "
import json, os

root = '$DRIVER_ROOT'
catalog = {'generated': '$(date -Iseconds)', 'models': {}}

for model in sorted(os.listdir(root)):
    model_dir = os.path.join(root, model)
    if not os.path.isdir(model_dir) or model.startswith('.'):
        continue

    version_file = os.path.join(model_dir, '.version')
    version_info = {}
    if os.path.exists(version_file):
        with open(version_file) as f:
            parts = f.read().strip().split('|')
            if len(parts) >= 3:
                version_info['md5'] = parts[0]
                version_info['updated'] = parts[1]
                version_info['files'] = parts[2]

    # Count drivers by category
    categories = {}
    for root_dir, dirs, files in os.walk(model_dir):
        rel = os.path.relpath(root_dir, model_dir)
        cat = rel.split(os.sep)[0] if rel != '.' else 'root'
        if cat not in categories:
            categories[cat] = 0
        categories[cat] += len(files)

    catalog['models'][model] = {
        'version': version_info,
        'categories': categories,
        'total_files': sum(categories.values())
    }

with open('$catalog', 'w') as f:
    json.dump(catalog, f, indent=2)
" 2>/dev/null && ok "Catalog index generated: $catalog" || warn "Catalog generation failed"
}

# ── Status ─────────────────────────────────────────────────────────────
do_status() {
    if [ ! -d "$DRIVER_ROOT" ]; then
        fail "Driver cache not initialized. Run: driver-cache.sh update"
        exit 1
    fi

    echo ""
    info "Driver Cache Status"
    info "Root: $DRIVER_ROOT"
    echo ""

    local total_size
    total_size=$(du -sh "$DRIVER_ROOT" 2>/dev/null | cut -f1)

    printf "%-25s %-12s %-10s %s\n" "Model" "Updated" "Files" "Size"
    printf "%s\n" "──────────────────────────────────────────────────────"

    local total_files=0
    local model_count=0
    for model_dir in "$DRIVER_ROOT"/*/; do
        [ -d "$model_dir" ] || continue
        local model
        model=$(basename "$model_dir")
        [[ "$model" == .* ]] && continue

        local version_file="$model_dir/.version"
        local updated="never"
        local files=0

        if [ -f "$version_file" ]; then
            updated=$(cut -d'|' -f2 "$version_file" 2>/dev/null | cut -c1-10 || echo "unknown")
            files=$(cut -d'|' -f3 "$version_file" 2>/dev/null | grep -oP '\d+' || echo "0")
        fi

        local size
        size=$(du -sh "$model_dir" 2>/dev/null | cut -f1)
        printf "%-25s %-12s %-10s %s\n" "$model" "${updated:0:10}" "$files" "$size"
        total_files=$((total_files + files))
        model_count=$((model_count + 1))
    done

    echo ""
    info "$model_count models, ~$total_files driver files, $total_size total"
}

# ── Sync from FOG Database ────────────────────────────────────────────
do_sync_fog() {
    local FOG_DB_HOST="${FOG_DB_HOST:-localhost}"
    local FOG_DB_NAME="${FOG_DB_NAME:-fog}"
    local FOG_DB_USER="${FOG_DB_USER:-fog}"
    local FOG_DB_PASS="${FOG_DB_PASS:-}"

    if [ -z "$FOG_DB_PASS" ]; then
        warn "FOG_DB_PASS not set. Attempting to read from FOG config..."
        FOG_DB_PASS=$(sudo cat /opt/fog/.fogsettings 2>/dev/null | grep -oP 'DB_PASS="?\K[^"]+' || echo "")
    fi

    if [ -z "$FOG_DB_PASS" ]; then
        warn "Cannot access FOG database. Using models.cfg instead."
        return 1
    fi

    info "Querying FOG database for unique client models..."

    local models
    models=$(MYSQL_PWD="$FOG_DB_PASS" mysql -h "$FOG_DB_HOST" -u "$FOG_DB_USER" "$FOG_DB_NAME" \
        -N -e "SELECT DISTINCT pm.model FROM printerModels pm WHERE pm.model != '' ORDER BY pm.model" 2>/dev/null \
        || mysql -h "$FOG_DB_HOST" -u "$FOG_DB_USER" "$FOG_DB_NAME" \
        -N -e "SELECT DISTINCT h.hostModel FROM hosts h WHERE h.hostModel != '' ORDER BY h.hostModel" 2>/dev/null \
        || echo "")

    if [ -z "$models" ]; then
        warn "No models found in FOG database"
        return 1
    fi

    # Convert to models.cfg format
    local tmpcfg=$(mktemp)
    echo "# Auto-generated from FOG database on $(date)" > "$tmpcfg"
    echo "$models" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "$line | $line | W10x64" >> "$tmpcfg"
    done

    # Merge with existing (keep deduped)
    if [ -f "$MODELS_CFG" ]; then
        cat "$MODELS_CFG" "$tmpcfg" | grep -v '^#' | grep -v '^$' | sort -u -t'|' -k1,1 > "${tmpcfg}.merged"
        mv "${tmpcfg}.merged" "$MODELS_CFG"
    else
        mv "$tmpcfg" "$MODELS_CFG"
    fi
    rm -f "$tmpcfg"

    ok "Models synced from FOG database. Config: $MODELS_CFG"
}

# ── Verify Model ───────────────────────────────────────────────────────
do_verify() {
    local model="$1"
    [ -n "$model" ] || { fail "Usage: driver-cache.sh verify <model>"; exit 1; }

    local model_dir="$DRIVER_ROOT/$model"
    if [ ! -d "$model_dir" ]; then
        fail "No cache for model: $model"
        exit 1
    fi

    local version_file="$model_dir/.version"
    if [ -f "$version_file" ]; then
        local updated files cab_url
        updated=$(cut -d'|' -f2 "$version_file" 2>/dev/null || echo "unknown")
        files=$(cut -d'|' -f3 "$version_file" 2>/dev/null || echo "unknown")
        cab_url=$(cut -d'|' -f4 "$version_file" 2>/dev/null || echo "unknown")

        info "Model: $model"
        info "Updated: $updated"
        info "Files:   $files"
        info "Source:  $cab_url"
        info "Size:    $(du -sh "$model_dir" | cut -f1)"

        # Check categories
        echo ""
        info "Driver categories:"
        for cat in "$model_dir"/*/; do
            [ -d "$cat" ] || continue
            local c=$(basename "$cat")
            local count
            count=$(find "$cat" -type f | wc -l)
            echo "  $c: $count files"
        done
    else
        warn "No version info for $model (cache may be incomplete)"
    fi
}

# ── List ───────────────────────────────────────────────────────────────
do_list() {
    if [ ! -d "$DRIVER_ROOT" ]; then
        fail "No driver cache found"
        exit 1
    fi

    echo "Cached models in $DRIVER_ROOT:"
    for d in "$DRIVER_ROOT"/*/; do
        [ -d "$d" ] || continue
        local m
        m=$(basename "$d")
        [[ "$m" == .* ]] && continue
        local ver="no version info"
        [ -f "$d/.version" ] && ver=$(cut -d'|' -f2 "$d/.version" | cut -c1-10)
        printf "  %-30s %s\n" "$m" "$ver"
    done
}

# ── Main ───────────────────────────────────────────────────────────────
case "${1:-help}" in
    update)     do_update ;;
    status)     do_status ;;
    verify)     do_verify "${2:-}" ;;
    list)       do_list ;;
    sync-fog)   do_sync_fog ;;
    setup)      setup ;;
    *)
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  update              Download/extract latest drivers for all models"
        echo "  status              Show cache status overview"
        echo "  verify <model>      Check driver cache for a specific model"
        echo "  list                List cached models"
        echo "  sync-fog            Pull model list from FOG database"
        echo "  setup               Install dependencies (curl, cabextract, samba)"
        ;;
esac

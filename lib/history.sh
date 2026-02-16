#!/bin/bash
# history.sh - Feature to compare with previous execution records

# Snapshot storage directory (dynamic resolution)
SNAPSHOT_DIR="${SNAPSHOT_DIR:-}"

# Snapshot management functions

# Initialize snapshot directory
init_snapshot_dir() {
    if [[ -z "$SNAPSHOT_DIR" ]]; then
        # Try to find resolution function or use default
        if declare -f get_snapshot_dir > /dev/null; then
            SNAPSHOT_DIR=$(get_snapshot_dir)
        else
            SNAPSHOT_DIR="$HOME/Library/Application Support/home-tidy/snapshots"
        fi
    fi
    mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || mkdir -p "$(dirname "$0")/../snapshots" 2>/dev/null
}

# Create snapshot of current state
# Format: path|size(bytes)|mtime
create_snapshot() {
    local target_paths=("$@")
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    # Add suffix argument (optional)
    local suffix="${MAX_SNAPSHOT_SUFFIX:-}"
    [[ -n "$suffix" ]] && timestamp="${timestamp}_${suffix}"
    
    local snapshot_file="${SNAPSHOT_DIR}/snapshot_${timestamp}.txt"
    
    init_snapshot_dir
    
    echo "# Home-Tidy Snapshot" > "$snapshot_file"
    echo "# Created: $(date '+%Y-%m-%d %H:%M:%S')" >> "$snapshot_file"
    echo "#" >> "$snapshot_file"
    
    local total_targets=${#target_paths[@]}
    local current_index=0
    
    for target in "${target_paths[@]}"; do
        current_index=$((current_index + 1))
        
        if [[ -d "$target" ]]; then
            # Progress indicator (stdout is clean, stderr for UI)
            echo -ne "${DIM}  ⏳ Scanning [$current_index/$total_targets]: $(basename "$target")...\033[0K\r${NC}" >&2
            
            # Use find + du -sk instead of du -d 1 -k (includes both files/directories, optimized with batch processing)
            # Find only 1st level sub-items and calculate size with du -sk
            
            # 1. Collect du results (size) first (use while read for path whitespace handling)
            find "$target" -mindepth 1 -maxdepth 1 -exec du -sk {} + 2>/dev/null | while read -r size_kb item_path; do
                [[ -z "$item_path" ]] && continue
                
                # Verify if file actually exists (race conditions, etc.)
                if [[ -e "$item_path" ]]; then
                    local name=$(basename "$item_path")
                    local size_bytes=$((size_kb * 1024))
                    local mtime=$(stat -f '%m' "$item_path" 2>/dev/null || echo "0")
                    
                    echo "${target}/${name}|${size_bytes}|${mtime}" >> "$snapshot_file"
                fi
            done
            
        elif [[ -f "$target" ]]; then
             # If target is a single file
             local name=$(basename "$target")
             local size=$(stat -f %z "$target" 2>/dev/null || echo 0)
             local mtime=$(stat -f '%m' "$target" 2>/dev/null || echo "0")
             echo "${target}|${size}|${mtime}" >> "$snapshot_file"
        fi
    done
    
    # Clear line and newline
    log_success "${DIM}Scan complete!                                " >&2
    
    echo "$snapshot_file"
}

# Find the latest snapshot file
get_latest_snapshot() {
    init_snapshot_dir
    ls -t "$SNAPSHOT_DIR"/snapshot_*.txt 2>/dev/null | head -n 1
}

# Find the second latest snapshot (for comparison)
get_previous_snapshot() {
    init_snapshot_dir
    # It may be better to exclude _post snapshots from comparison
    ls -t "$SNAPSHOT_DIR"/snapshot_*.txt 2>/dev/null | grep -v "_post" | sed -n '2p'
}

# Comparison functions


# Compare two snapshots and print differences
compare_snapshots() {
    local old_snapshot="$1"
    local new_snapshot="$2"
    
    if [[ ! -f "$old_snapshot" || ! -f "$new_snapshot" ]]; then
        echo -e "${DIM}No snapshots to compare.${NC}"
        return 1
    fi
    
    local changes_found=false
    
    echo ""
    echo -e "${BOLD}▒ Change Tracking (Compared to previous run)${NC}"
    echo ""
    
    # New items
    echo ""
    echo -e "${DIM}📁 [New Items]${NC}"
    while IFS='|' read -r path size mtime || [[ -n "$path" ]]; do
        [[ "$path" =~ ^# ]] && continue
        [[ -z "$path" ]] && continue
        
        if ! grep -q "^${path}|" "$old_snapshot" 2>/dev/null; then
            local hr_size=$(format_size "$size")
            echo -e "${DIM}  + $path ($hr_size)${NC}"
            changes_found=true
        fi
    done < "$new_snapshot"
    
    # Size changes
    echo ""
    echo -e "${DIM}📈 [Significant Changes (Increase >= 50%)]${NC}"
    while IFS='|' read -r new_path new_size new_mtime || [[ -n "$new_path" ]]; do
        [[ "$new_path" =~ ^# ]] && continue
        [[ -z "$new_path" ]] && continue
        
        local old_line=$(grep "^${new_path}|" "$old_snapshot" 2>/dev/null)
        if [[ -n "$old_line" ]]; then
            local old_size=$(echo "$old_line" | cut -d'|' -f2)
            if [[ $old_size -gt 0 && $new_size -gt 0 ]]; then
                local change_percent=$(( (new_size - old_size) * 100 / old_size ))
                if [[ $change_percent -ge 50 ]]; then
                    local old_hr=$(format_size "$old_size")
                    local new_hr=$(format_size "$new_size")
                    echo -e "${DIM}  ↑ $new_path: $old_hr → $new_hr (+${change_percent}%)${NC}"
                    changes_found=true
                fi
            fi
        fi
    done < "$new_snapshot"
    
    if [[ "$changes_found" == false ]]; then
        echo ""
        log_success "${DIM}No significant changes compared to previous run."
    fi
    
    echo ""
}

# Compare with the last execution
compare_with_previous() {
    local current_snapshot="$1"
    local previous_snapshot=$(get_previous_snapshot)
    
    if [[ -z "$previous_snapshot" ]]; then
        echo ""
        echo -e "${DIM}[i] No previous snapshot found. (First run)${NC}"
        return 0
    fi
    
    local prev_date=$(basename "$previous_snapshot" | sed 's/snapshot_//' | sed 's/.txt//' | cut -d'_' -f1)
    local formatted_date="${prev_date:0:4}-${prev_date:4:2}-${prev_date:6:2}"
    
    echo -e "${DIM}[i] Comparing with previous snapshot: $formatted_date${NC}"
    
    compare_snapshots "$previous_snapshot" "$current_snapshot"
}

# Snapshot cleanup (delete old ones, keep recent N)
cleanup_old_snapshots() {
    local keep_count=${1:-10}
    init_snapshot_dir
    
    local count=$(ls -1 "$SNAPSHOT_DIR"/snapshot_*.txt 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ $count -gt $keep_count ]]; then
        local to_delete=$((count - keep_count))
        ls -t "$SNAPSHOT_DIR"/snapshot_*.txt | tail -n "$to_delete" | xargs rm -f
        echo -e "${DIM}[i] Deleted ${to_delete} old snapshots.${NC}"
    fi
}

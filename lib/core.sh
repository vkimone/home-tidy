#!/bin/bash
# core.sh - Home-Tidy core logic (scan, delete)

# =====================================
# Scan function (optimized version)
# =====================================

# Extract target items from snapshot (removes filesystem scan)
scan_all_targets_from_snapshot() {
    local snapshot_file="$1"
    local whitelist_file="$2"
    local results=()
    
    # Load whitelist patterns into memory
    local whitelist_patterns=()
    if [[ -f "$whitelist_file" ]]; then
        while IFS= read -r pattern || [[ -n "$pattern" ]]; do
            [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
            whitelist_patterns+=("$(echo "$pattern" | xargs)")
        done < "$whitelist_file"
    fi
    
    echo "" >&2
    echo -e "${BOLD}▒ Cache Item Analysis (Snapshot Based)${NC}" >&2
    echo "" >&2
    
    local total_count=0
    local total_size=0
    
    # Calculate total lines for progress indication
    local total_lines=$(grep -c . "$snapshot_file")
    local current_line=0
    
    # Update progress every 100 lines for better responsiveness
    local update_interval=100
    
    while IFS='|' read -r path size mtime || [[ -n "$path" ]]; do
        current_line=$((current_line + 1))
        
        # Display progress using stderr to avoid pipe pollution
        if (( current_line % update_interval == 0 )); then
            local percent=$(( current_line * 100 / total_lines ))
            echo -ne "${DIM}  ⏳ Analyzing... [${percent}%] (${current_line}/${total_lines})\033[0K\r${NC}" >&2
        fi
        
        # Ignore header or empty lines
        [[ "$path" =~ ^# || -z "$path" ]] && continue
        
        local is_safe=false
        for pattern in "${whitelist_patterns[@]}"; do
            # Exact match
            if [[ "$path" == "$pattern" ]]; then
                is_safe=true
                break
            fi
            
            # Wildcard patterns (fnmatch style)
            if [[ "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
                # shellcheck disable=SC2053
                if [[ "$path" == $pattern ]]; then
                    is_safe=true
                    break
                fi
            fi
        done
        
        # Whitelist check (memory-based)
        if [[ "$is_safe" == true ]]; then
             # Avoid calling log_debug for performance
            continue
        fi
        
        # Add to results
        results+=("${path}|${size}")
        
        total_count=$((total_count + 1))
        total_size=$((total_size + size))
        
    done < "$snapshot_file"
    
    # Clear progress
    #echo -e "${DIM} Analysis complete! (${total_lines} lines processed)${NC}        " >&2
    log_success "Analysis complete! (${total_lines} lines processed)"

    local hr_size=$(format_size $total_size)
    log_info "Identified $total_count items, $hr_size for cleanup"
    
    printf '%s\n' "${results[@]}"
}

# (Legacy) File-based whitelist check - kept for backward compatibility, currently unused
is_whitelisted() {
    local name="$1"
    local whitelist_file="$2"
    
    [[ ! -f "$whitelist_file" ]] && return 1
    
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
        pattern=$(echo "$pattern" | xargs)
        
        [[ "$name" == "$pattern" ]] && return 0
        
        if [[ "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
            # shellcheck disable=SC2053
            [[ "$name" == $pattern ]] && return 0
        fi
    done < "$whitelist_file"
    
    return 1
}

# =====================================
# Deletion function
# =====================================

# Delete a single item (optimized for direct deletion)
delete_item() {
    local item_path="$1"
    local dry_run="$2"
    
    if [[ ! -e "$item_path" ]]; then
        echo "" >&2
        log_warning "Item does not exist: $item_path"
        return 1
    fi
    
    local size=$(get_dir_size_bytes "$item_path")
    local hr_size=$(format_size $size)
    
    # Final security check before deletion
    if is_forbidden_path "$item_path"; then
        echo "" >&2
        log_error "CRITICAL SECURITY BREACH: Attempted to delete forbidden path: $item_path"
        return 1
    fi

    if [[ "$dry_run" == true ]]; then
        log_overwrite "[DRY-RUN] To be deleted: $item_path ($hr_size)"
        return 0
    fi
    
    # Direct deletion (Silent, high-speed, minimal permission issues)
    local error_msg
    error_msg=$(rm -rf "$item_path" 2>&1)
    if [[ $? -eq 0 ]]; then
        log_overwrite "Deleted: $item_path ($hr_size)"
        return 0
    else
        echo "" >&2
        log_error "Deletion failed: $item_path"
        if [[ -n "$error_msg" ]]; then
            log_error "  Cause: $error_msg"
            if [[ "$error_msg" == *"Permission denied"* ]]; then
                log_warning "${YELLOW}  Tip: Try running with 'sudo' for protected system files.${NC}"
            fi
        fi
        return 1
    fi
}

# Delete multiple items
delete_items() {
    local dry_run="$1"
    shift 1
    local items=("$@")
    
    local failed_count=0
    
    echo ""
    if [[ "$dry_run" == true ]]; then
        echo -e "${BOLD}▒ Pending Deletion List (Dry Run Mode)${NC}"
    else
        echo -e "${BOLD}▒ Deletion in Progress${NC}"
    fi
    echo ""
    
    for item_line in "${items[@]}"; do
        [[ -z "$item_line" ]] && continue
        
        local path=$(echo "$item_line" | cut -d'|' -f1)
        local size=$(echo "$item_line" | cut -d'|' -f2)
        
        if delete_item "$path" "$dry_run"; then
            # Update global variables
            G_DELETED_COUNT=$((G_DELETED_COUNT + 1))
            G_DELETED_SIZE=$((G_DELETED_SIZE + size))
        else
            failed_count=$((failed_count + 1))
        fi
    done
    
    # Remove individual result summaries (integrated output later)
    if [[ $failed_count -gt 0 ]]; then
        echo ""
        log_error "Failed to delete: $failed_count items"
    fi
}

# Print final result summary
print_result_summary() {
    local dry_run="$1"
    
    echo ""
    echo ""
    echo -e "${BOLD}▒ Result Summary${NC}"
    echo ""
    
    # Total result (sentence format)
    local hr_deleted_size=$(format_size $G_DELETED_SIZE)
    
    if [[ $G_DELETED_SIZE -gt 0 ]]; then
        if [[ "$dry_run" == true ]]; then
            printf "${GREEN}%s${NC} ${DIM}Total items to clean: %d items (%s)${NC}\n" "[✓]" "$G_DELETED_COUNT" "$hr_deleted_size"
        else
            printf "${GREEN}%s${NC} ${DIM}Total items cleaned: %d items (%s)${NC}\n" "[✓]" "$G_DELETED_COUNT" "$hr_deleted_size"
        fi
    else
        printf "${DIM}%s${NC} ${DIM}No items to clean.${NC}\n" "[i]"
    fi
    echo ""
}

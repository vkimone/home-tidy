#!/bin/bash
# =========================================================
# Home-Tidy - macOS Home Folder Cache Cleanup Tool
# =========================================================
# Usage: ./home-tidy.sh [options]
# Options:
#   --dry-run        Display items to be deleted without actual deletion
#   --execute        Perform actual deletion (Default)
#   --compare-only   Perform change tracking only (No deletion)
#   --no-trash       Direct deletion instead of moving to Trash (Use with caution!)
#   --verbose        Show detailed logs
#   --help           Display this help message
# =========================================================

set -e

# Handle Ctrl+C (SIGINT)
cleanup_and_exit() {
    echo ""
    log_warning "Interrupted by user."
    
    # Terminate all background jobs in the current process group
    kill 0 2>/dev/null || true
    
    finalize_report
    exit 130
}

trap cleanup_and_exit SIGINT SIGTERM

# Set paths relative to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LIB_DIR="${SCRIPT_DIR}/lib"
VERSION_FILE="${SCRIPT_DIR}/VERSION"

# Set directories dynamically
get_snapshot_dir() {
    local user_dir="$HOME/Library/Application Support/home-tidy/snapshots"
    local project_dir="${SCRIPT_DIR}/snapshots"
    
    # Try user directory - must exist (or be created) AND be writable
    if ([[ -d "$user_dir" ]] || mkdir -p "$user_dir" 2>/dev/null) && [[ -w "$user_dir" ]]; then
        echo "$user_dir"
    else
        # Fallback to project directory
        mkdir -p "$project_dir" 2>/dev/null
        echo "$project_dir"
    fi
}

get_report_dir() {
    local user_dir="$HOME/Library/Application Support/home-tidy/logs"
    local project_dir="${SCRIPT_DIR}/reports"
    
    # Try user directory - must exist (or be created) AND be writable
    if ([[ -d "$user_dir" ]] || mkdir -p "$user_dir" 2>/dev/null) && [[ -w "$user_dir" ]]; then
        echo "$user_dir"
    else
        # Fallback to project directory
        mkdir -p "$project_dir" 2>/dev/null
        echo "$project_dir"
    fi
}

# Initial directory resolution
SNAPSHOT_DIR=$(get_snapshot_dir)
REPORT_DIR=$(get_report_dir)

# Load libraries
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/history.sh"
source "${LIB_DIR}/core.sh"

# =====================================
# Default settings
# =====================================
DRY_RUN=false
COMPARE_ONLY=false
VERBOSE=false
CFG_SECTION=""
ACTION=""
ACTION_ARG=""

# Global variables for result aggregation
G_DELETED_COUNT=0
G_DELETED_SIZE=0

# =====================================
# Path & Config Management Functions
# =====================================

# Get config file path (user config takes priority over project config)
get_config_path() {
    local filename="$1"
    local user_config="$HOME/Library/Application Support/home-tidy/config/$filename"
    local project_config="${CONFIG_DIR}/$filename"
    
    # Priority: user config > project config
    if [[ -f "$user_config" ]]; then
        echo "$user_config"
    else
        echo "$project_config"
    fi
}

# Initialize user config directory (first run or Homebrew install)
init_user_config() {
    local user_config_dir="$HOME/Library/Application Support/home-tidy/config"
    
    # Skip if already initialized
    [[ -f "$user_config_dir/target.conf" ]] && return 0
    
    # Create directory
    mkdir -p "$user_config_dir" 2>/dev/null || {
        log_debug "Could not create user config directory (will use project configs)"
        return 1
    }
    
    # Copy default configs from project
    local copied=false
    for conf_file in target.conf whitelist.conf; do
        if [[ -f "${CONFIG_DIR}/$conf_file" ]]; then
            if cp "${CONFIG_DIR}/$conf_file" "$user_config_dir/" 2>/dev/null; then
                copied=true
            fi
        fi
    done
    
    if [[ "$copied" == true ]]; then
        log_info "Initialized user configuration in $user_config_dir"
    fi
    
    return 0
}


# =====================================
# Version
# =====================================
show_version() {
    local version="unknown"
    if [[ -f "$VERSION_FILE" ]]; then
        version=$(cat "$VERSION_FILE")
    fi
    echo "home-tidy version $version"
}

# =====================================
# Help
# =====================================
show_help() {
    cat << EOF

Usage: $(basename "$0") [options]

Options:
  --execute                 Perform actual deletion (Default)
  --dry-run                 Display items to be deleted without actual deletion
  --compare-only            Perform change tracking only (No deletion)
  --list-target             Show target directories
  --list-whitelist          Show whitelist patterns
  --section <name>          Specify section for adding items
  --add-target <p>          Add target directory
  --remove-target <p>       Remove target directory
  --add-whitelist <w>       Add whitelist pattern
  --remove-whitelist <w>    Remove whitelist pattern
  --verbose                 Show detailed logs
  --version                 Display version information
  --help                    Display this help message

Example:
  $(basename "$0")                                               # Perform actual deletion
  $(basename "$0") --dry-run                                     # Analyze in Dry-run mode
  $(basename "$0") --compare-only                                # Track changes only
  $(basename "$0") --add-target ~/.test --section mysection      # Add target directory
  $(basename "$0") --remove-target ~/.test                       # Remove target directory


Data storage location: ~/Library/Application Support/home-tidy
  - Snapshots: snapshots/
  - Reports: logs/

EOF
}

# =====================================
# Parse arguments
# =====================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --execute)
                DRY_RUN=false
                shift
                ;;
            --compare-only)
                COMPARE_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            --help|-h)
                print_banner
                show_help
                exit 0
                ;;
            --list-target)
                ACTION="list-target"
                shift
                ;;
            --list-whitelist)
                ACTION="list-whitelist"
                shift
                ;;
            --section)
                CFG_SECTION="$2"
                shift 2
                ;;
            --add-target)
                ACTION="add-target"
                ACTION_ARG="$2"
                shift 2
                ;;
            --remove-target)
                ACTION="remove-target"
                ACTION_ARG="$2"
                shift 2
                ;;
            --add-whitelist)
                ACTION="add-whitelist"
                ACTION_ARG="$2"
                shift 2
                ;;
            --remove-whitelist)
                ACTION="remove-whitelist"
                ACTION_ARG="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# =====================================
# Main logic
# =====================================
main() {
    parse_args "$@"
    
    # Export resolved directories for libraries
    export SNAPSHOT_DIR
    export REPORT_DIR
    
    # Initialize user config (first run copies defaults)
    init_user_config
    
    # Resolve config file paths (user config takes priority)
    local target_conf=$(get_config_path "target.conf")
    local whitelist_conf=$(get_config_path "whitelist.conf")

    # Handle actions
    case "$ACTION" in
        list-target)
            list_config_file "$target_conf" "Current Target Directories"
            exit 0
            ;;
        list-whitelist)
            list_config_file "$whitelist_conf" "Current Whitelist Patterns"
            exit 0
            ;;
        add-target)
            local new_path=$(expand_path "$ACTION_ARG")
            if validate_target_path "$new_path"; then
                add_to_config "$target_conf" "$ACTION_ARG" "$CFG_SECTION"
            fi
            exit 0
            ;;
        remove-target)
            remove_from_config "$target_conf" "$ACTION_ARG"
            exit 0
            ;;
        add-whitelist)
            add_to_config "$whitelist_conf" "$ACTION_ARG" "$CFG_SECTION"
            exit 0
            ;;
        remove-whitelist)
            remove_from_config "$whitelist_conf" "$ACTION_ARG"
            exit 0
            ;;
    esac

    print_banner
    
    # Initialize report
    init_report "$REPORT_DIR"
    
    # Check config files
    if [[ ! -f "$target_conf" ]]; then
        log_error "Target config file not found: $target_conf"
        exit 1
    fi
    
    # Read target paths
    local targets=()
    while IFS= read -r line; do
        targets+=("$line")
    done <<EOF
$(read_config_paths "$target_conf")
EOF
    
    log_info "Loaded ${#targets[@]} target directories"
    for t in "${targets[@]}"; do
        log_debug "  - $t"
    done
    
    # Create snapshot of current state
    log_info "Creating snapshot of current state..."
    local current_snapshot
    current_snapshot=$(create_snapshot "${targets[@]}")
    log_success "Snapshot created: $(basename "$current_snapshot")"
    
    # Compare with previous run
    compare_with_previous "$current_snapshot"
    
    # Exit if only comparing
    if [[ "$COMPARE_ONLY" == true ]]; then
        cleanup_old_snapshots 10
        finalize_report
        echo ""
        log_info "Comparison mode complete. No deletion performed."
        exit 0
    fi
    
    # Analysis based on target snapshot (optimized)
    local items=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && items+=("$line")
    done <<EOF
$(scan_all_targets_from_snapshot "$current_snapshot" "$whitelist_conf")
EOF
    
    if [[ ${#items[@]} -eq 0 ]]; then
        log_info "No items to delete."
        finalize_report
        exit 0
    fi
    
    # Confirmation before actual deletion (only in execute mode)
    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        log_warning "⚠️  Executing actual deletion!"
        if ! ask_confirm "Are you sure you want to proceed?"; then
            log_info "Cancelled by user."
            finalize_report
            exit 0
        fi
    fi
    
    # Perform deletion
    delete_items "$DRY_RUN" "${items[@]}"
    
    # If in execution mode, create post-cleanup snapshot and analyze effects
    if [[ "$DRY_RUN" == false ]]; then
        log_info "Creating post-cleanup snapshot..."
        MAX_SNAPSHOT_SUFFIX="post"
        local post_snapshot
        post_snapshot=$(create_snapshot "${targets[@]}")
        log_success "Post-cleanup snapshot created"
        
        # Analyze effects (output removed, only snapshot created)
        # calculate_reclaimed_space "$current_snapshot" "$post_snapshot"
    fi
    
    # Cleanup old snapshots
    cleanup_old_snapshots 10
    
    # Print final result summary
    print_result_summary "$DRY_RUN"
    
    # Finalize report
    finalize_report
    
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run complete."
    else
        log_success "Cleanup complete!"
    fi
}

# Execute
main "$@"

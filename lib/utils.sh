#!/bin/bash
# utils.sh - Home-Tidy utility function collection

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Global variables
REPORT_FILE=""
VERBOSE=false

# Banner print function
print_banner() {
    echo -e "${GRAY}"
    cat << "EOF"

█░█░█▀█░█▄█░█▀▀░░░▀█▀░▀█▀░█▀▄░█░█
█▀█░█░█░█░█░█▀▀░░░░█░░░█░░█░█░░█░
▀░▀░▀▀▀░▀░▀░▀▀▀░░░░▀░░▀▀▀░▀▀░░░▀░

macOS Home Folder Cache Cleanup Tool

EOF
    echo -e "${NC}"
}

# Logging functions

log_info() {
    local message="$1"
    echo -e "${DIM}[i]${NC} ${DIM}${message}${NC}" >&2
    if [[ -n "$REPORT_FILE" ]]; then
        echo "[i] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
    fi
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[✓]${NC} ${DIM}${message}${NC}" >&2
    if [[ -n "$REPORT_FILE" ]]; then
        echo "[✓] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
    fi
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[!]${NC} ${DIM}${message}${NC}" >&2
    if [[ -n "$REPORT_FILE" ]]; then
        echo "[!] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
    fi
}

log_error() {
    local message="$1"
    echo -e "${RED}[x]${NC} ${DIM}${message}${NC}" >&2
    if [[ -n "$REPORT_FILE" ]]; then
        echo "[x] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
    fi
}

log_debug() {
    local message="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "[d] ${DIM}${message}${NC}" >&2
        if [[ -n "$REPORT_FILE" ]]; then
            echo "[d] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
        fi
    fi
}

log_overwrite() {
    local message="$1"
    # Overwrite on terminal (CR + Clear Line)
    echo -ne "\r\033[K${DIM}[i]${NC} ${DIM}${message}${NC}" >&2
    # Record with newline in report file
    if [[ -n "$REPORT_FILE" ]]; then
        echo "[i] $message" | perl -pe 's/\e\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
    fi
}

# Size related functions

# Convert bytes to human-readable format
format_size() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

# Directory size (in bytes)
get_dir_size_bytes() {
    local path="$1"
    # -e checks for existence (file or directory)
    if [[ -e "$path" ]]; then
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
    else
        echo 0
    fi
}

# Available space on current volume (in bytes)
get_available_space() {
    df -k "$HOME" | tail -1 | awk '{print $4 * 1024}'
}

# User input functions

ask_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -r -p "$prompt [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# Report related functions


init_report() {
    local report_dir="${1:-$HOME/Library/Application Support/home-tidy/logs}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    mkdir -p "$report_dir"
    REPORT_FILE="${report_dir}/report_${timestamp}.txt"
    
    echo "▒ Home-Tidy Execution Report" > "$REPORT_FILE"
    echo " Execution Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    log_info "Report file created: $REPORT_FILE"
}

finalize_report() {
    if [[ -n "$REPORT_FILE" ]]; then
        echo "" >> "$REPORT_FILE"
        echo "▒ Report End: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
        log_success "Report saved: $REPORT_FILE"
    fi
}

# Path utilities

        # Tilde expansion
expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

# Unexpand home directory path to ~
unexpand_path() {
    local path="$1"
    local h=$(expand_path "~")
    echo "${path/#$h/~}"
}

# Path normalization (expansion + trailing slash removal)
normalize_path() {
    local path=$(expand_path "$1")
    echo "${path%/}"
}

# Read list of paths from config file
read_config_paths() {
    local config_file="$1"
    local paths=()
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignore comments, empty lines, and section headers ([Section])
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*\[.*\] ]] && continue
        # Remove leading/trailing whitespace
        line=$(echo "$line" | xargs)
        # Tilde expansion
        local expanded=$(expand_path "$line")
        
        # Security validation (only for target.conf)
        if [[ "$(basename "$config_file")" == "target.conf" ]]; then
            if ! validate_target_path "$expanded" true; then
                continue
            fi
        fi
        
        paths+=("$expanded")
    done < "$config_file"
    
    printf '%s\n' "${paths[@]}"
}

# Security and path validation

# Check for forbidden paths that must never be deleted
is_forbidden_path() {
    local target_path=$(expand_path "$1")
    # Path normalization (Trailing slash removal)
    target_path="${target_path%/}"
    
    local h=$(expand_path "~")
    local forbidden_list=(
        "$h"
        "$h/Documents"
        "$h/Desktop"
        "$h/Downloads"
        "$h/.ssh"
        "$h/.gnupg"
        "/"
        "/System"
        "/Library"
        "/Applications"
        "/Users"
    )
    
    for forbidden in "${forbidden_list[@]}"; do
        if [[ "$target_path" == "$forbidden" ]]; then
            return 0
        fi
        # Protect parent directories rather than subdirectories
        # But while / is forbidden, /Users is explicitly listed in forbidden_list.
    done
    
    return 1
}

# Validate target path and security
validate_target_path() {
    local path="$1"
    local silent="${2:-false}"
    
    # 1. Directory existence check
    if [[ ! -d "$path" ]]; then
        [[ "$silent" == false ]] && log_error "Directory does not exist: $path"
        return 1
    fi
    
    # 2. Forbidden list check
    if is_forbidden_path "$path"; then
        [[ "$silent" == false ]] && log_error "FORBIDDEN PATH: This directory is protected and cannot be a target: $path"
        return 1
    fi
    
    # 3. Outside of HOME directory check (security recommendation)
    if [[ "$path" != "$HOME"* && "$path" != "/tmp"* ]]; then
         [[ "$silent" == false ]] && log_warning "Path is outside of HOME directory. Exercise caution: $path"
    fi

    return 0
}

# Config file management utilities

# Add item to config file
add_to_config() {
    local config_file="$1"
    local item="$2"
    local section="${3:-Others}"
    local section_header="[$section]"
    
    # Ensure we're using user config directory
    local user_config_dir="$HOME/Library/Application Support/home-tidy/config"
    local filename=$(basename "$config_file")
    
    # If user config doesn't exist yet, create it from project config
    if [[ ! -f "$user_config_dir/$filename" ]]; then
        mkdir -p "$user_config_dir" 2>/dev/null
        if [[ -f "${SCRIPT_DIR}/config/$filename" ]]; then
            cp "${SCRIPT_DIR}/config/$filename" "$user_config_dir/$filename" 2>/dev/null
        elif [[ -f "$config_file" ]]; then
            cp "$config_file" "$user_config_dir/$filename" 2>/dev/null
        fi
    fi
    
    # Use user config
    config_file="$user_config_dir/$filename"
    
    local norm_item=$(normalize_path "$item")
    
    # Check for duplicates (normalize and compare all paths)
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*\[.*\] ]] && continue
        local norm_line=$(normalize_path "$line")
        if [[ "$norm_item" == "$norm_line" ]]; then
            log_warning "Item already exists (as $line): $item"
            return 0
        fi
    done < "$config_file"
    
    # Keep tilde style when saving (unexpand)
    local storage_item=$(unexpand_path "$item")
    local temp_file=$(mktemp /tmp/home-tidy-config-add.XXXXXX)
    
    # Check if section header exists
    if grep -Fxq "$section_header" "$config_file" 2>/dev/null; then
        # If section exists: insert after the last item in that section
        local start_line=$(grep -nFx "$section_header" "$config_file" | cut -d: -f1)
        local next_section_line=$(tail -n +$((start_line + 1)) "$config_file" | grep -n "^\[" | head -n 1 | cut -d: -f1)
        
        if [[ -n "$next_section_line" ]]; then
            local insert_at=$((start_line + next_section_line))
            sed "${insert_at}i\\
$storage_item
" "$config_file" > "$temp_file"
        else
            cat "$config_file" > "$temp_file"
            [[ -n $(tail -c 1 "$config_file") ]] && echo "" >> "$temp_file"
            echo "$storage_item" >> "$temp_file"
        fi
    else
        cat "$config_file" > "$temp_file"
        [[ -n $(tail -c 1 "$config_file") ]] && echo "" >> "$temp_file"
        echo -e "\n$section_header" >> "$temp_file"
        echo "$storage_item" >> "$temp_file"
    fi
    
    mv "$temp_file" "$config_file"
    log_success "Added to $(basename "$config_file") in section $section_header: $storage_item"
}

# Remove item from config file
remove_from_config() {
    local config_file="$1"
    local item="$2"
    local norm_item=$(normalize_path "$item")
    local target_line=""
    
    # Ensure we're using user config directory
    local user_config_dir="$HOME/Library/Application Support/home-tidy/config"
    local filename=$(basename "$config_file")
    
    # If user config doesn't exist yet, create it from project config
    if [[ ! -f "$user_config_dir/$filename" ]]; then
        mkdir -p "$user_config_dir" 2>/dev/null
        if [[ -f "${SCRIPT_DIR}/config/$filename" ]]; then
            cp "${SCRIPT_DIR}/config/$filename" "$user_config_dir/$filename" 2>/dev/null
        elif [[ -f "$config_file" ]]; then
            cp "$config_file" "$user_config_dir/$filename" 2>/dev/null
        fi
    fi
    
    # Use user config
    config_file="$user_config_dir/$filename"
    
    # Find matching original line using normalized path
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*\[.*\] ]] && continue
        local norm_line=$(normalize_path "$line")
        if [[ "$norm_item" == "$norm_line" ]]; then
            target_line="$line"
            break
        fi
    done < "$config_file"
    
    if [[ -z "$target_line" ]]; then
        log_error "Item not found in $(basename "$config_file"): $item"
        return 1
    fi
    
    # Delete using a temporary file
    local temp_file=$(mktemp /tmp/home-tidy-config.XXXXXX)
    grep -Fv "$target_line" "$config_file" > "$temp_file"
    mv "$temp_file" "$config_file"
    log_success "Removed from $(basename "$config_file"): $target_line"
}

# List contents of config file
list_config_file() {
    local config_file="$1"
    local title="$2"
    
    echo -e "${BOLD}▒ $title${NC}"
    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found."
        return 1
    fi
    
    local count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Handle section headers ([Section])
        if [[ "$line" =~ ^[[:space:]]*\[(.*)\] ]]; then
            local section_name="${BASH_REMATCH[1]}"
            echo -e "\n  ▒ $section_name${NC}"
            continue
        fi
        
        echo -e "  ${DIM}  - $line${NC}"
        count=$((count + 1))
    done < "$config_file"
    
    if [[ $count -eq 0 ]]; then
        echo -e "  ${GRAY}(Empty)${NC}"
    fi
    echo ""
}

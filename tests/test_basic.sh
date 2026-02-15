#!/bin/bash
# test_basic.sh - Repository basic feature (scan/delete) tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests/sandbox"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/utils.sh"
# Logging setup for testing (Uses stderr, so works normally in tests)
VERBOSE=true

# Test environment setup
setup() {
    echo "[SETUP] Initializing test environment: $TEST_DIR"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    
    # Create dummy cache directories
    mkdir -p "$TEST_DIR/CacheRoot/App1"
    mkdir -p "$TEST_DIR/CacheRoot/App2"
    mkdir -p "$TEST_DIR/Logs"
    
    # Create dummy files
    dd if=/dev/zero of="$TEST_DIR/CacheRoot/App1/cache.db" bs=1024 count=100 2>/dev/null # 100KB
    dd if=/dev/zero of="$TEST_DIR/CacheRoot/App2/data.tmp" bs=1024 count=200 2>/dev/null # 200KB
    dd if=/dev/zero of="$TEST_DIR/Logs/app.log" bs=1024 count=50 2>/dev/null           # 50KB
    
    # Create test config files
    echo "$TEST_DIR/CacheRoot" > "$TEST_DIR/target.conf"
    echo "$TEST_DIR/Logs" >> "$TEST_DIR/target.conf"
    
    echo "whitelist_item" > "$TEST_DIR/whitelist.conf"
}

teardown() {
    echo "[TEARDOWN] Cleaning up test environment"
    rm -rf "$TEST_DIR"
}

# Test cases

run_test_scan() {
    echo "------------------------------------------------"
    echo "[TEST] Scan feature test"
    echo "------------------------------------------------"
    
    source "${LIB_DIR}/history.sh"
    source "${LIB_DIR}/core.sh"
    
    # Snapshot directory override (for testing)
    SNAPSHOT_DIR="${TEST_DIR}/snapshots"
    mkdir -p "$SNAPSHOT_DIR"
    
    # 1. Snapshot creation test
    local targets=("$TEST_DIR/CacheRoot" "$TEST_DIR/Logs")
    local snapshot_file
    snapshot_file=$(create_snapshot "${targets[@]}")
    
    if [[ ! -f "$snapshot_file" ]]; then
        echo "❌ Snapshot creation failed"
        return 1
    fi
    echo "✅ Snapshot creation success: $snapshot_file"
    
    # 2. Verify snapshot contents
    # App1 and App2 should be included
    # Current create_snapshot logic: Scan all target/* items (files/folders) (optimized)
    
    local count=$(grep -c "$TEST_DIR" "$snapshot_file")
    if [[ $count -ge 3 ]]; then
        echo "✅ Verified number of snapshot items ($count)"
    else
        echo "❌ Insufficient snapshot items (Expected: 3, Actual: $count)"
        cat "$snapshot_file"
        return 1
    fi
    
    # 3. Scan function integration test
    local items
    items=$(scan_all_targets_from_snapshot "$snapshot_file" "$TEST_DIR/whitelist.conf")
    
    local scan_count=$(echo "$items" | wc -l)
    if [[ $scan_count -ge 3 ]]; then # Might vary due to empty line logic, but should be 3 (App1, App2, log)
        echo "✅ Scan integration success ($scan_count items)"
    else
        echo "❌ Scan integration failed"
        echo "$items"
        return 1
    fi
}

run_test_delete_dryrun() {
    echo "------------------------------------------------"
    echo "[TEST] Deletion (Dry Run) test"
    echo "------------------------------------------------"
    
    # delete_item function is in core.sh
    
    local target_file="$TEST_DIR/CacheRoot/App1"
    
    # Dry Run = true
    delete_item "$target_file" true false
    
    if [[ -d "$target_file" ]]; then
        echo "✅ Verified Dry Run (files not deleted)"
    else
        echo "❌ Dry Run failed (files deleted)"
        return 1
    fi
}

run_test_delete_execute() {
    echo "------------------------------------------------"
    echo "[TEST] Deletion (Execute) test - No Trash"
    echo "------------------------------------------------"
    
    local target_file="$TEST_DIR/CacheRoot/App1"
    
    # Dry Run = false, Trash = false (direct deletion)
    delete_item "$target_file" false false
    
    if [[ ! -e "$target_file" ]]; then
        echo "✅ Verified deletion (files removed)"
    else
        echo "❌ Deletion failed (files remain)"
        return 1
    fi
}

# Main execution
setup
run_test_scan
run_test_delete_dryrun
run_test_delete_execute
teardown
echo "------------------------------------------------"
echo "All tests complete"
echo "------------------------------------------------"

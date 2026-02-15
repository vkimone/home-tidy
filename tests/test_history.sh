#!/bin/bash
# test_history.sh - Change detection and comparison logic tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests/sandbox_history"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/history.sh" # includes compare_snapshots function

# Test environment setup
setup() {
    echo "[SETUP] Initializing history test environment"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Test cases

run_test_comparison() {
    echo "------------------------------------------------"
    echo "[TEST] Snapshot comparison (change detection) test"
    echo "------------------------------------------------"
    
    local snap1="$TEST_DIR/snap1.txt"
    local snap2="$TEST_DIR/snap2.txt"
    
    # 1. Create baseline snapshot
    echo "# Home-Tidy Snapshot" > "$snap1"
    echo "/Users/test/cache/AppA|102400|1000" >> "$snap1" # 100KB
    echo "/Users/test/cache/AppB|204800|1000" >> "$snap1" # 200KB
    
    # 2. Create modified snapshot
    echo "# Home-Tidy Snapshot" > "$snap2"
    echo "/Users/test/cache/AppA|102400|1000" >> "$snap2" # No change
    # AppB deleted
    echo "/Users/test/cache/AppC|51200|1000" >> "$snap2"  # AppC added (50KB)
    echo "/Users/test/cache/AppD|10240000|1000" >> "$snap2" # AppD large addition
    
    # 3. Run comparison and capture output
    local output
    output=$(compare_snapshots "$snap1" "$snap2")
    
    echo "$output"
    
    # 4. Verification
    if echo "$output" | grep -q "New Items"; then
        if echo "$output" | grep -q "AppC"; then
            echo "✅ 'New Items' detected"
        else
            echo "❌ 'AppC' detection failed"
            return 1
        fi
    else
        echo "❌ 'New Items' section missing"
        return 1
    fi
    
    if echo "$output" | grep -q "Deleted Items"; then
        if echo "$output" | grep -q "AppB"; then
            echo "✅ 'Deleted Items' detection success"
        else
            echo "❌ 'AppB' detection failed"
            return 1
        fi
    else
        echo "❌ 'Deleted Items' section missing"
        return 1
    fi
}

run_test_space_delta() {
    echo "------------------------------------------------"
    echo "[TEST] Reclaimed space calculation test"
    echo "------------------------------------------------"
    
    local snap_pre="$TEST_DIR/pre.txt"
    local snap_post="$TEST_DIR/post.txt"
    
    # Pre: 100KB + 200KB = 300KB
    echo "/path/a|102400|0" > "$snap_pre"
    echo "/path/b|204800|0" >> "$snap_pre"
    
    # Post: 100KB (200KB deleted)
    echo "/path/a|102400|0" > "$snap_post"
    
    local output
    output=$(calculate_reclaimed_space "$snap_pre" "$snap_post")
    
    echo "$output"
    
    # 200KB = Approx 195KB or 0.19 MB etc.
    # Must include "KB" according to format_size logic
    if echo "$output" | grep -q "Reclaimed space"; then
        echo "✅ Space calculation output verified"
    else
        echo "❌ Space calculation failed"
        return 1
    fi
}

# Main execution
setup
run_test_comparison
run_test_space_delta
teardown
echo "------------------------------------------------"
echo "History test complete"
echo "------------------------------------------------"

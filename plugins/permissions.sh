#!/bin/bash
# Plugin: Permissions & Repair
# Description: Helpers to fix "Permission Denied" and ownership issues

# Function: make_executable
# Usage: LEO calls this after writing a script
# Example: TOOL: EXEC_CMD make_executable isam/run_me.sh
make_executable() {
    local target=$1
    if [ -z "$target" ]; then echo "Usage: make_executable <filename>"; return; fi

    if [ -f "$target" ]; then
        chmod +x "$target"
        echo "SUCCESS: '$target' is now executable (+x)."
    else
        echo "ERROR: File '$target' not found."
    fi
}

# Function: fix_owner
# Usage: LEO calls this if it accidentally created root-owned files
# Example: TOOL: EXEC_CMD fix_owner isam/
fix_owner() {
    local target=$1
    if [ -z "$target" ]; then target="."; fi
    
    echo "Attempting to fix ownership for: $target"
    
    # Try normal chown first (fast)
    if chown -R "$(whoami)" "$target" 2>/dev/null; then
        echo "SUCCESS: Ownership fixed."
    else
        # Fallback to sudo (interactive - user might need to type password)
        echo "Standard fix failed. Trying sudo (Password may be required)..."
        if sudo chown -R "$(whoami)" "$target"; then
            echo "SUCCESS: Ownership fixed via sudo."
        else
            echo "ERROR: Could not change ownership."
        fi
    fi
}

# Function: check_perms
# Usage: Checks if a file is writable/executable
check_perms() {
    local target=$1
    ls -l "$target"
}

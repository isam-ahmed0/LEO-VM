#!/bin/bash
# Plugin: Directory Explorer
# Description: Gives LEO advanced vision of the file system

# Function: dir_tree
# Usage: LEO uses this to see folder structure
# Example: TOOL: EXEC_CMD dir_tree isam/
dir_tree() {
    local target="${1:-.}" # Default to current dir
    
    echo "=== FOLDER STRUCTURE: $target ==="
    
    if command -v tree &> /dev/null; then
        # Limit depth to 3 levels to keep chat clean
        tree -L 3 -F "$target"
    else
        # Fallback if 'tree' isn't installed
        find "$target" -maxdepth 3 -not -path '*/.*' | sort
    fi
    echo "================================="
}

# Function: dir_list
# Usage: Shows hidden files and sizes
# Example: TOOL: EXEC_CMD dir_list isam/
dir_list() {
    local target="${1:-.}"
    echo "=== DETAILED LIST: $target ==="
    ls -lah --group-directories-first "$target"
}

# Function: dir_find
# Usage: Locates a file anywhere inside the current folder
# Example: TOOL: EXEC_CMD dir_find config.json
dir_find() {
    local query="$1"
    echo "=== SEARCHING FOR: $query ==="
    find . -type f -name "*$query*" 2>/dev/null
}

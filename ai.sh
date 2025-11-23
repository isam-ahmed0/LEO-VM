#!/bin/bash
# ==============================================================================
# LEO AI v4.1 - ULTIMATE AUTONOMOUS AGENT
# Powered by Gemini Pro (v1) | By Isam Ahmed
# Capabilities: Self-Fix, Plugins, Web, VM Control, Real Knowledge
# ==============================================================================

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
API_KEY_FILE="$HOME/.leo_ai_key"
HISTORY_FILE="/tmp/leo_v4_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"
PLUGIN_DIR="$SCRIPT_DIR/plugins"
VM_SCRIPT="$SCRIPT_DIR/vm.sh"

# === USER CONFIGURATION ===
# Using v1 endpoint as requested
API_URL="https://generativelanguage.googleapis.com/v1/models"
# Recommended: gemini-1.5-pro (Most capable public model)
# Change to gemini-2.5-pro ONLY if you have specific whitelist access.
MODEL="gemini-2.5-pro" 

# Directories
TARGET_DIRS="$SCRIPT_DIR/isam $SCRIPT_DIR/LEO-VM"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

# ==============================================================================
# 1. Initialization & Real Knowledge Loading
# ==============================================================================

init_system() {
    mkdir -p "$SCRIPT_DIR/isam" "$SCRIPT_DIR/LEO-VM" "$PLUGIN_DIR"
    touch "$MEMORY_FILE"
}

get_time() { date +"%H:%M:%S"; }

# Loads plugins dynamically
load_plugins() {
    local p_context=""
    if [ -d "$PLUGIN_DIR" ]; then
        for plugin in "$PLUGIN_DIR"/*.sh; do
            if [ -f "$plugin" ]; then
                source "$plugin"
                p_context+="Plugin Loaded: $(basename "$plugin")\n"
            fi
        done
    fi
    echo "$p_context"
}

# SAFELY loads vm.sh functions (Surgery Method)
load_vm_functions() {
    if [ -f "$VM_SCRIPT" ]; then
        # 1. Strip 'set -e' to prevent crashes
        # 2. Comment out traps so vm.sh doesn't kill LEO
        # 3. Comment out direct calls to main_menu
        grep -v "^set -euo pipefail" "$VM_SCRIPT" | \
        sed 's/^trap /# trap /' | \
        sed 's/^main_menu/# main_menu/' | \
        sed 's/^check_dependencies/# check_dependencies/' \
        > "/tmp/leo_vm_safe.sh"
        
        source "/tmp/leo_vm_safe.sh"
    fi
}

get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        GEMINI_API_KEY=$(cat "$API_KEY_FILE")
    else
        clear
        echo -e "${YELLOW}LEO AI Setup${NC}"
        echo -e "Enter Google Gemini API Key:"
        read -s GEMINI_API_KEY
        echo "$GEMINI_API_KEY" > "$API_KEY_FILE"
    fi
}

# ==============================================================================
# 2. The Brain (System Prompt)
# ==============================================================================

get_system_prompt() {
    local plugins=$(load_plugins)
    local memory=$(cat "$MEMORY_FILE")
    # Feed actual file structure to AI
    local fs_context=$(ls -R "$SCRIPT_DIR/isam" "$SCRIPT_DIR/LEO-VM" 2>/dev/null | head -n 30)
    
    local sys_context="You are LEO AI (v4.1), an Autonomous System Administrator by Isam Ahmed.
    
    *** IDENTITY ***
    User: $(whoami) | Dir: $SCRIPT_DIR | Time: $(date)
    
    *** REAL-TIME KNOWLEDGE ***
    VM Manager: DETECTED (Functions loaded)
    Filesystem Preview:
    $fs_context
    
    *** CAPABILITIES ***
    1. SELF-MODIFICATION: You can read 'ai.sh' and overwrite it.
    2. FILESYSTEM: Read/Write access to isam/ and LEO-VM/.
    3. PLUGINS: $plugins
    4. WEB: Use SEARCH_WEB tool.
    
    *** TOOL PROTOCOL (Strict Format) ***
    Output tools on a new line.
    TOOL: READ_FILE <path>
    TOOL: WRITE_FILE <path> (Content on next lines, end with END_WRITE)
    TOOL: EXEC_CMD <command>
    TOOL: SEARCH_WEB <query>
    TOOL: MEMORY_SAVE <fact>
    
    *** RULES ***
    1. To manage VMs, use: TOOL: EXEC_CMD start_vm <name> (or stop_vm, create_new_vm).
    2. If an error occurs, read the file, analyze, and fix it.
    3. Be concise.
    
    *** MEMORY ***
    $memory
    "
    echo "$sys_context" | jq -Rsa .
}

init_history() {
    echo "{\"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": $(get_system_prompt)}]}]}" > "$HISTORY_FILE"
}

# ==============================================================================
# 3. Tool Execution Engine
# ==============================================================================

execute_tool() {
    local tool_line="$1"
    local full_response="$2"
    local output=""
    local has_action=false

    # --- READ_FILE ---
    if [[ "$tool_line" == TOOL:\ READ_FILE* ]]; then
        local path=$(echo "$tool_line" | cut -d' ' -f3-)
        if [ -f "$path" ]; then
            output="FILE CONTENT ($path):\n$(cat "$path")"
        else
            output="ERROR: File $path not found."
        fi
        has_action=true
    fi

    # --- EXEC_CMD ---
    if [[ "$tool_line" == TOOL:\ EXEC_CMD* ]]; then
        local cmd=$(echo "$tool_line" | cut -d' ' -f3-)
        echo -e "${RED}   >>> Running: $cmd${NC}"
        
        # Capture output and error
        local cmd_out
        cmd_out=$(eval "$cmd" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            output="SUCCESS:\n$cmd_out"
        else
            output="ERROR (Exit Code $exit_code):\n$cmd_out\n\nINSTRUCTION: Analyze error and fix."
        fi
        has_action=true
    fi

    # --- WRITE_FILE ---
    if [[ "$tool_line" == TOOL:\ WRITE_FILE* ]]; then
        local path=$(echo "$tool_line" | cut -d' ' -f3-)
        # Extract content between TOOL line and END_WRITE
        local content=$(echo "$full_response" | sed -n "/TOOL: WRITE_FILE/,/END_WRITE/p" | sed '1d;$d')
        
        echo -e "${YELLOW}   >>> Writing: $path${NC}"
        mkdir -p "$(dirname "$path")"
        echo "$content" > "$path"
        output="File written successfully."
        
        # SELF-UPDATE LOGIC
        if [[ "$path" == *"$0"* || "$path" == *"ai.sh"* ]]; then
            echo -e "${MAGENTA}   >>> LEO UPDATED ITSELF. RELOADING...${NC}"
            exec "$0"
        fi
        has_action=true
    fi

    # --- SEARCH_WEB ---
    if [[ "$tool_line" == TOOL:\ SEARCH_WEB* ]]; then
        local query=$(echo "$tool_line" | cut -d' ' -f3-)
        echo -e "${BLUE}   >>> Searching: $query${NC}"
        if command -v ddgr &> /dev/null; then
            output=$(ddgr --json -n 2 "$query" 2>&1)
        else
            output="ERROR: 'ddgr' not installed. Mock result for '$query'."
        fi
        has_action=true
    fi

    if [ "$has_action" = true ]; then
        send_to_leo "TOOL_OUTPUT:\n$output" "tool_feedback"
    fi
}

# ==============================================================================
# 4. Communication & UI
# ==============================================================================

display_header() {
    clear
    cat << "EOF"
========================================================================
LEO 888

885,088 888,088 88 88

BY ISAM AHMED
========================================================================
EOF
    echo -e "${CYAN}Powered by $MODEL (v1)${NC}"
    echo -e "${GRAY}Filesystem: ENABLED | VM Knowledge: ACTIVE${NC}"
    echo "----------------------------------------------------------"
}

spinner() {
    local pid=$1
    local spinstr='|/-\'
    tput civis
    echo -ne "${PURPLE}   LEO is Thinking... "
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    tput cnorm
    echo -ne "${NC}"
}

send_to_leo() {
    local input="$1"
    local mode="$2"

    # Update History
    local temp_hist=$(mktemp)
    jq --arg text "$input" '.contents += [{"role": "user", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # Call API (Background)
    local response_file=$(mktemp)
    curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE > "$response_file" &
    
    local curl_pid=$!
    
    # VISUALS: Show spinner only for user input, not internal tool loops
    if [ "$mode" != "tool_feedback" ]; then
        echo ""; spinner $curl_pid; echo ""
    else
        wait $curl_pid
    fi

    local raw_response=$(cat "$response_file")
    rm "$response_file"

    # Parse Response
    local ai_text=$(echo "$raw_response" | jq -r '.candidates[0].content.parts[0].text // empty')
    
    if [ -z "$ai_text" ]; then
        local err_msg=$(echo "$raw_response" | jq -r '.error.message // "Unknown Error"')
        echo -e "${RED}API Error: $err_msg${NC}"
        return
    fi

    # Update History
    jq --arg text "$ai_text" '.contents += [{"role": "model", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # Display AI Response
    echo -e "\r${CYAN}┌── [LEO AI]${NC}"
    echo -e "${CYAN}│${NC} $ai_text"
    echo -e "${CYAN}└──────────────────────────────────────────${NC}"

    # Parse & Execute Tools
    while read -r line; do
        if [[ "$line" == TOOL:* ]]; then
            execute_tool "$line" "$ai_text"
        fi
    done <<< "$ai_text"
}

# ==============================================================================
# 5. Main Loop
# ==============================================================================

main() {
    init_system
    get_api_key
    load_vm_functions # Safe Load
    init_history
    display_header

    while true; do
        # User Input (Blocking)
        echo -e "\n${GREEN}┌── [YOU]${NC}"
        read -p "╰──➤ " user_input

        if [[ "$user_input" =~ ^(exit|quit|leave)$ ]]; then
            echo -e "${PURPLE}Saving memory... Goodbye.${NC}"
            break
        fi

        if [ -n "$user_input" ]; then
            send_to_leo "$user_input" "user"
        fi
    done
}

# Cleanup
trap 'rm -f /tmp/leo_v4_history.json /tmp/leo_vm_safe.sh; echo -e "\n${RED}Exiting.${NC}"; exit' SIGINT
main

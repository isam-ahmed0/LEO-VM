#!/bin/bash
# =================================================
# LEO AI - The Intelligent Terminal Assistant
# Powered by Gemini Pro | Variant of vm.sh
# Feature: AUTO-MEMORY & FULL VM Management
# =================================================

# Determine where the script is running from
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Configuration
API_KEY_FILE="$HOME/.leo_ai_key"
VM_DIR="${VM_DIR:-$HOME/vms}"
HISTORY_FILE="/tmp/leo_chat_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"
VM_SCRIPT="$SCRIPT_DIR/vm.sh"

# === USER CONFIGURATION ===
MODEL="gemini-2.5-pro"
API_URL="https://generativelanguage.googleapis.com/v1/models"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# =============================
# Library Loading (Robust)
# =============================
load_vm_functions() {
    if [ -f "$VM_SCRIPT" ]; then
        # We perform 'surgery' on vm.sh to make it a safe library.
        # We strip traps and main execution logic.
        grep -v "^set -euo pipefail" "$VM_SCRIPT" | \
        sed 's/^trap cleanup EXIT/# trap cleanup EXIT/g' | \
        sed 's/^check_dependencies/# check_dependencies/g' | \
        sed 's/^main_menu/# main_menu/g' | \
        sed 's/if \[\[ "${BASH_SOURCE\[0\]}" == "${0}" \]\]; then/if false; then/g' \
        > /tmp/leo_vm_lib.sh
        
        # Source the safe library
        set +e
        source /tmp/leo_vm_lib.sh
        set -e
        
        if ! command -v stop_vm &> /dev/null; then
             echo -e "${RED}[ERROR] Failed to load VM functions.${NC}"
             exit 1
        fi
        
        # Restore LEO's trap
        trap 'rm -f "$HISTORY_FILE" /tmp/leo_vm_lib.sh; echo -e "\n${BLUE}LEO Shutting down...${NC}"; exit 0' SIGINT SIGTERM EXIT
    else
        echo -e "${RED}[ERROR] vm.sh not found at: $VM_SCRIPT${NC}"
        exit 1
    fi
}

# =============================
# Helpers
# =============================

get_time() {
    date +"%H:%M:%S"
}

display_header() {
    clear
    cat << "EOF"
========================================================================
LEO 888

885,088 888,088 88 88

BY ISAM AHMED
========================================================================
EOF
    echo -e "${CYAN}Powered by Google Gemini Pro ($MODEL)${NC}"
    echo -e "${BLUE}Type 'exit' to leave. Type 'mem' to view memory.${NC}"
    echo "------------------------------------------------------------------------"
}

get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        GEMINI_API_KEY=$(cat "$API_KEY_FILE")
    else
        echo -e "${YELLOW}Welcome to LEO AI.${NC}"
        read -p "Enter your Gemini API Key: " GEMINI_API_KEY
        echo "$GEMINI_API_KEY" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
    fi
}

# =============================
# AI Context
# =============================

get_system_context() {
    local context="You are LEO AI, an advanced VM Manager Assistant. 
    Current User: $(whoami)
    
    CAPABILITIES:
    1. Manage VMs (Create, Start, Stop, Edit, Info, Delete).
    2. LEARN from the user automatically.
    
    *** AUTO-MEMORY PROTOCOL ***
    If the user mentions a fact/preference, append: >>MEMORY: [fact]
    
    *** ACTION COMMANDS ***
    Output these commands strictly on a new line to control the VM manager:
    - To create a VM:       ACTION: CREATE
    - To start a VM:        ACTION: START <vm_name>
    - To stop a VM:         ACTION: STOP <vm_name>
    - To show info:         ACTION: INFO <vm_name>
    - To edit config:       ACTION: EDIT <vm_name>
    - To delete VM:         ACTION: DELETE <vm_name>
    
    CURRENT VM STATUS:
    "

    # List VMs
    if [ -d "$VM_DIR" ]; then
        local vm_list=$(find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null)
        if [ -n "$vm_list" ]; then
            for vm in $vm_list; do
                # We assume functions are loaded, use is_vm_running logic manually
                local status="STOPPED"
                if pgrep -f "qemu-system-x86_64.*$vm" >/dev/null; then status="RUNNING"; fi
                # Read config strictly for context
                source "$VM_DIR/$vm.conf" 2>/dev/null || true
                context+=" - $vm | OS: $OS_TYPE | Port: $SSH_PORT | Status: $status\n"
            done
        else
            context+="No VMs found.\n"
        fi
    fi

    if [ -f "$MEMORY_FILE" ]; then
        context+="\nLONG-TERM MEMORY:\n$(cat "$MEMORY_FILE")\n"
    fi

    echo "$context"
}

init_chat() {
    local sys_prompt=$(get_system_context)
    jq -n --arg role "user" --arg text "$sys_prompt" \
       '{contents: [{role: $role, parts: [{text: $text}]}]}' > "$HISTORY_FILE"
}

# =============================
# Action Handler
# =============================

handle_ai_actions() {
    local ai_response="$1"
    local needs_refresh=false
    
    # 1. Handle Auto-Memory
    if echo "$ai_response" | grep -q ">>MEMORY:"; then
        local memories=$(echo "$ai_response" | grep -o ">>MEMORY: .*" | sed 's/>>MEMORY: //')
        echo "$memories" >> "$MEMORY_FILE"
        echo -e "${GRAY}[$(get_time)] 🧠 Memory Updated${NC}"
        needs_refresh=true
    fi

    # 2. Handle Actions
    if echo "$ai_response" | grep -q "ACTION: CREATE"; then
        echo -e "${YELLOW}[$(get_time)] Launching Creation Wizard...${NC}"
        create_new_vm
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: START"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: START .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Starting VM: $vm_name...${NC}"
        start_vm "$vm_name"
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: STOP"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: STOP .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Stopping VM: $vm_name...${NC}"
        stop_vm "$vm_name"
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: INFO"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: INFO .*" | awk '{print $3}')
        show_vm_info "$vm_name"
    fi
    
    if echo "$ai_response" | grep -q "ACTION: DELETE"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: DELETE .*" | awk '{print $3}')
        delete_vm "$vm_name"
        needs_refresh=true
    fi
    
    if echo "$ai_response" | grep -q "ACTION: EDIT"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: EDIT .*" | awk '{print $3}')
        edit_vm_config "$vm_name"
        needs_refresh=true
    fi

    if [ "$needs_refresh" = true ]; then
        init_chat
    fi
}

chat_with_leo() {
    local user_input="$1"
    
    local temp_hist=$(mktemp)
    jq --arg text "$user_input" \
       '.contents += [{role: "user", parts: [{text: $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    echo -e "${PURPLE}[$(get_time)] LEO is thinking...${NC}"

    local response=$(curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE)

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
    
    if [ -z "$ai_text" ]; then
         echo -e "${RED}[$(get_time)] Error: No response or API error.${NC}"
         return
    fi

    echo -e "\r${GREEN}[$(get_time)] LEO AI:${NC}"
    echo -e "$ai_text" | sed '/ACTION:/d' | sed '/>>MEMORY:/d'
    echo ""

    handle_ai_actions "$ai_text"

    jq --arg text "$ai_text" \
       '.contents += [{role: "model", parts: [{text: $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"
}

# =============================
# Main Loop
# =============================

main() {
    load_vm_functions
    get_api_key
    display_header
    init_chat

    while true; do
        read -p "$(echo -e "${GRAY}[$(get_time)]${NC} ${CYAN}[YOU] > ${NC}")" user_input
        
        if [[ "$user_input" =~ ^(exit|quit|bye)$ ]]; then
            echo -e "${BLUE}LEO: Goodbye!${NC}"
            break
        fi

        if [[ "$user_input" == "menu" ]]; then
             if [ -f "$VM_SCRIPT" ]; then "$VM_SCRIPT"; display_header; continue; fi
        fi

        if [[ "$user_input" == "mem" ]]; then
             if [ -f "$MEMORY_FILE" ]; then cat "$MEMORY_FILE"; else echo "Memory Empty"; fi
             continue
        fi

        if [ -n "$user_input" ]; then
            chat_with_leo "$user_input"
        fi
    done
}

main

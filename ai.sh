#!/bin/bash
# =================================================
# LEO AI - The Intelligent Terminal Assistant
# Powered by Gemini Pro | Variant of vm.sh
# Feature: AUTO-MEMORY & VM Management
# =================================================

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Configuration
API_KEY_FILE="$HOME/.leo_ai_key"
VM_DIR="${VM_DIR:-$HOME/vms}"
HISTORY_FILE="/tmp/leo_chat_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"
# FIXED: Finds vm.sh in the same folder as ai.sh
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
# Library Loading (FIXED)
# =============================
load_vm_functions() {
    if [ -f "$VM_SCRIPT" ]; then
        # Create a clean library version of vm.sh
        # 1. Comment out the main_menu call so it doesn't start the menu
        # 2. Comment out traps so it doesn't kill the AI on exit
        # 3. Comment out check_dependencies to avoid noise
        grep -v "^set -euo pipefail" "$VM_SCRIPT" | \
        sed 's/^\s*main_menu/# main_menu/g' | \
        sed 's/^\s*trap /# trap /g' | \
        sed 's/^\s*check_dependencies/# check_dependencies/g' \
        > /tmp/leo_vm_lib.sh
        
        # Source the functions safely
        set +e
        source /tmp/leo_vm_lib.sh
        set -e
        
        # Verify if it worked
        if ! command -v stop_vm &> /dev/null; then
             echo -e "${RED}[ERROR] Failed to load VM functions from $VM_SCRIPT.${NC}"
             echo "Make sure vm.sh defines a function called 'stop_vm'."
        fi
        
        # Set cleanup trap for AI
        trap 'rm -f "$HISTORY_FILE" /tmp/leo_vm_lib.sh; echo -e "\n${BLUE}LEO Shutting down...${NC}"; exit 0' SIGINT SIGTERM EXIT
    else
        echo -e "${RED}[ERROR] vm.sh not found at: $VM_SCRIPT${NC}"
        echo -e "${YELLOW}Please ensure vm.sh is in the same folder as ai.sh${NC}"
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
888     888'Y88   e88 88e   
888     888 ,'Y  d888 888b  
888     888C8   C8888 8888D 
888  ,d 888 ",d  Y888 888P  
888,d88 888,d88   "88 88"

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
        echo -e "To function, I need a Google Gemini API Key."
        read -p "Enter your API Key: " GEMINI_API_KEY
        if [ -z "$GEMINI_API_KEY" ]; then
            echo -e "${RED}API Key is required.${NC}"
            exit 1
        fi
        echo "$GEMINI_API_KEY" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
        echo -e "${GREEN}Key saved securely.${NC}"
        sleep 1
    fi
}

# =============================
# AI Context & Auto-Memory
# =============================

get_system_context() {
    local context="You are LEO AI, an advanced VM Manager Assistant. 
    Current User: $(whoami)
    
    CAPABILITIES:
    1. Manage VMs (Create, Stop, Edit, Info).
    2. LEARN from the user automatically.
    
    IMPORTANT RULES:
    1. **STARTING VMs**: FORBIDDEN. Reply: 'I cannot start VMs. Please type 'menu' or use ./vm.sh option 2.'
    2. **ACTIONS**: Output specific ACTION COMMANDS alone on a new line.
    
    *** AUTO-MEMORY PROTOCOL ***
    If the user mentions a fact/preference to remember, append this tag to the response:
    >>MEMORY: [The fact to be saved]
    
    ACTION COMMANDS:
    - To create a VM:       ACTION: CREATE
    - To stop a VM:         ACTION: STOP <vm_name>
    - To edit config:       ACTION: EDIT <vm_name>
    - To show info:         ACTION: INFO <vm_name>
    
    CURRENT VM STATUS:
    "

    # List VMs
    if [ -d "$VM_DIR" ]; then
        local vm_list=$(find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null)
        if [ -n "$vm_list" ]; then
            for vm in $vm_list; do
                source "$VM_DIR/$vm.conf" 2>/dev/null || true
                local status="STOPPED"
                if pgrep -f "qemu-system-x86_64.*$vm" >/dev/null; then status="RUNNING"; fi
                context+=" - $vm | OS: $OS_TYPE | IP/Port: $SSH_PORT | Status: $status\n"
            done
        else
            context+="No VMs found.\n"
        fi
    fi

    # Inject Long-Term Memory
    if [ -f "$MEMORY_FILE" ] && [ -s "$MEMORY_FILE" ]; then
        context+="\nLONG-TERM MEMORY:\n"
        context+=$(cat "$MEMORY_FILE")
        context+="\n"
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
        echo -e "${GRAY}[$(get_time)] 🧠 Memory Updated: $memories${NC}"
        needs_refresh=true
    fi

    # 2. Handle VM Actions
    if echo "$ai_response" | grep -q "ACTION: CREATE"; then
        echo -e "${YELLOW}[$(get_time)] Launching Creation Wizard...${NC}"
        if command -v create_new_vm &>/dev/null; then
            create_new_vm
            needs_refresh=true
        else
            echo -e "${RED}[ERROR] Function 'create_new_vm' not found.${NC}"
        fi
    fi

    if echo "$ai_response" | grep -q "ACTION: STOP"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: STOP .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Stopping VM: $vm_name...${NC}"
        if command -v stop_vm &>/dev/null; then
            stop_vm "$vm_name"
            needs_refresh=true
        else
             echo -e "${RED}[ERROR] Function 'stop_vm' not found.${NC}"
        fi
    fi

    if echo "$ai_response" | grep -q "ACTION: EDIT"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: EDIT .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Editing VM: $vm_name...${NC}"
        if command -v edit_vm_config &>/dev/null; then
            edit_vm_config "$vm_name"
            needs_refresh=true
        else
            echo -e "${RED}[ERROR] Function 'edit_vm_config' not found.${NC}"
        fi
    fi

    if echo "$ai_response" | grep -q "ACTION: INFO"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: INFO .*" | awk '{print $3}')
        if command -v show_vm_info &>/dev/null; then
            show_vm_info "$vm_name"
        else
            echo -e "${RED}[ERROR] Function 'show_vm_info' not found.${NC}"
        fi
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

    local error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [ -n "$error_msg" ]; then
        echo -e "${RED}[$(get_time)] API Error: $error_msg${NC}"
        return
    fi

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')
    
    if [ -z "$ai_text" ]; then
         echo -e "${RED}[$(get_time)] LEO returned no content.${NC}"
         return
    fi

    # Display Response (Hide internal tags)
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
        
        if [[ "$user_input" =~ ^(exit|quit|bye|logout)$ ]]; then
            echo -e "${BLUE}LEO: Goodbye!${NC}"
            break
        fi

        if [ -z "$user_input" ]; then
            continue
        fi

        if [[ "$user_input" == "menu" ]] || [[ "$user_input" == "vm" ]]; then
             if [ -f "$VM_SCRIPT" ]; then
                 "$VM_SCRIPT"
                 display_header
                 continue
             fi
        fi

        if [[ "$user_input" == "mem" ]]; then
             echo -e "${YELLOW}=== LEO'S AUTO-MEMORY ===${NC}"
             if [ -f "$MEMORY_FILE" ]; then
                 cat "$MEMORY_FILE"
                 echo -e "\n${YELLOW}To clear, type: clear mem${NC}"
             else
                 echo "Memory is empty."
             fi
             continue
        fi

        if [[ "$user_input" == "clear mem" ]]; then
             rm -f "$MEMORY_FILE"
             echo -e "${RED}Memory wiped.${NC}"
             init_chat
             continue
        fi

        chat_with_leo "$user_input"
    done
}

main

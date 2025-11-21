#!/bin/bash
# =================================================
# LEO AI - The Intelligent Terminal Assistant
# Powered by Gemini Pro | Variant of vm.sh
# Feature: AUTO-MEMORY & VM Management
# =================================================

# Configuration
API_KEY_FILE="$HOME/.leo_ai_key"
VM_DIR="${VM_DIR:-$HOME/vms}"
HISTORY_FILE="/tmp/leo_chat_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"
VM_SCRIPT="./vm.sh"

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
# Library Loading
# =============================
load_vm_functions() {
    if [ -f "$VM_SCRIPT" ]; then
        sed '$d' "$VM_SCRIPT" > /tmp/leo_vm_lib.sh
        set +e
        source /tmp/leo_vm_lib.sh 2>/dev/null
        set -e
        trap 'rm -f "$HISTORY_FILE" /tmp/leo_vm_lib.sh; echo -e "\n${BLUE}LEO Shutting down...${NC}"; exit 0' SIGINT SIGTERM EXIT
    else
        echo -e "${RED}[WARN] vm.sh not found. VM management features disabled.${NC}"
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
# AI Context & Auto-Memory Logic
# =============================

get_system_context() {
    local context="You are LEO AI, an advanced VM Manager Assistant with AUTO-MEMORY. 
    Current User: $(whoami)
    
    CAPABILITIES:
    1. Manage VMs (Create, Stop, Edit, Info).
    2. LEARN from the user automatically.
    
    IMPORTANT RULES:
    1. **STARTING VMs**: FORBIDDEN. Reply: 'I cannot start VMs. Please type 'menu' or use ./vm.sh option 2.'
    2. **ACTIONS**: Output specific ACTION COMMANDS alone on a new line.
    
    *** AUTO-MEMORY PROTOCOL ***
    You must actively listen for user preferences, names, configurations, or specific instructions.
    If the user mentions a fact that should be remembered for future sessions, append this tag to the end of your response:
    >>MEMORY: [The fact to be saved]
    
    Example:
    User: 'My main server IP is 192.168.1.50'
    You: 'Understood. >>MEMORY: Main server IP is 192.168.1.50'
    
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
        fi
    fi

    # Inject Long-Term Memory
    if [ -f "$MEMORY_FILE" ] && [ -s "$MEMORY_FILE" ]; then
        context+="\nLONG-TERM MEMORY (Things you learned previously):\n"
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
    
    # 1. Handle Auto-Memory (The >>MEMORY: tag)
    # We use grep to find lines starting with >>MEMORY:
    if echo "$ai_response" | grep -q ">>MEMORY:"; then
        # Extract the text after the tag
        local memories=$(echo "$ai_response" | grep -o ">>MEMORY: .*" | sed 's/>>MEMORY: //')
        
        # Save to file
        echo "$memories" >> "$MEMORY_FILE"
        
        # Visual indicator that memory was updated (Subtle)
        echo -e "${GRAY}[$(get_time)] 🧠 Memory Updated: $memories${NC}"
        needs_refresh=true
    fi

    # 2. Handle VM Actions
    if echo "$ai_response" | grep -q "ACTION: CREATE"; then
        echo -e "${YELLOW}[$(get_time)] Launching Creation Wizard...${NC}"
        create_new_vm
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: STOP"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: STOP .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Stopping VM: $vm_name...${NC}"
        stop_vm "$vm_name"
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: EDIT"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: EDIT .*" | awk '{print $3}')
        echo -e "${YELLOW}[$(get_time)] Editing VM: $vm_name...${NC}"
        edit_vm_config "$vm_name"
        needs_refresh=true
    fi

    if echo "$ai_response" | grep -q "ACTION: INFO"; then
        local vm_name=$(echo "$ai_response" | grep -o "ACTION: INFO .*" | awk '{print $3}')
        show_vm_info "$vm_name"
    fi

    # If memory or VM state changed, refresh the system prompt
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

    # Display Response
    # We pipe through sed to remove the internal ACTION lines AND the >>MEMORY lines
    # so the user sees a clean response.
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

        # Menu Shortcuts
        if [[ "$user_input" == "menu" ]] || [[ "$user_input" == "vm" ]]; then
             if [ -f "./vm.sh" ]; then
                 ./vm.sh
                 display_header
                 continue
             fi
        fi

        # Memory Management
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

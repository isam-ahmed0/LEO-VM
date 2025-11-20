#!/bin/bash
set -euo pipefail

# =================================================
# LEO AI - The Intelligent Terminal Assistant
# Powered by Gemini Pro | Variant of vm.sh
# =================================================

# Configuration
API_KEY_FILE="$HOME/.leo_ai_key"
VM_DIR="${VM_DIR:-$HOME/vms}"
HISTORY_FILE="/tmp/leo_chat_history.json"
MODEL="gemini-1.5-pro-latest" # Using 1.5 Pro (High capability)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# =============================
# Initialization & Helpers
# =============================

display_header() {
    clear
    cat << "EOF"
========================================================================
  888     888'Y88   e88 a   
888     888 ,'Y  d888 888b  
888     888C8   C8888 8888D 
888  ,d 888 ",d  Y888 888P  
888,d88 888,d88   "88 88"   
                            
                            
                                     
        BY ISAM AHMED
========================================================================
EOF
    echo -e "${CYAN}Powered by Google Gemini Pro${NC}"
    echo -e "${BLUE}Type 'exit', 'quit', or 'bye' to leave.${NC}"
    echo "------------------------------------------------------------------------"
}

check_deps() {
    local deps=("curl" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}[ERROR] Missing dependency: $dep${NC}"
            echo "Please install it: sudo apt install $dep"
            exit 1
        fi
    done
}

get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        GEMINI_API_KEY=$(cat "$API_KEY_FILE")
    else
        echo -e "${YELLOW}Welcome to LEO AI.${NC}"
        echo -e "To function, I need a Google Gemini API Key."
        echo "Get one here: https://aistudio.google.com/app/apikey"
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
# Context Gathering
# =============================

get_system_context() {
    local context="You are LEO AI, a highly advanced Linux terminal assistant. 
    Current User: $(whoami)
    Current Shell: $SHELL
    Current Directory: $(pwd)
    
    Your goal is to help the user manage their system, write code, fix scripts, and manage VMs.
    
    KNOWLEDGE BASE - VM MANAGER (vm.sh):
    The user has a script named 'vm.sh' in this directory (or nearby) used to manage QEMU VMs.
    The VMs are stored in: $VM_DIR
    "

    # List existing VMs
    if [ -d "$VM_DIR" ]; then
        context+="\nDETECTED VIRTUAL MACHINES:\n"
        local vm_list=$(find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null)
        if [ -n "$vm_list" ]; then
            for vm in $vm_list; do
                # Read minimal config info
                source "$VM_DIR/$vm.conf" 2>/dev/null || true
                context+=" - Name: $vm | OS: ${OS_TYPE:-Unknown} | RAM: ${MEMORY:-Unknown} | IP/Port: $SSH_PORT\n"
                
                # Check if running
                if pgrep -f "qemu-system-x86_64.*$vm" >/dev/null; then
                    context+="   STATUS: RUNNING\n"
                else
                    context+="   STATUS: STOPPED\n"
                fi
            done
        else
            context+="No VMs created yet.\n"
        fi
    else
        context+="VM Directory ($VM_DIR) does not exist yet.\n"
    fi

    context+="\nINSTRUCTIONS FOR VM MANAGEMENT:
    1. If the user wants to START, STOP, or CREATE a VM, advise them to run the menu command: ./vm.sh
    2. Specifically, tell them: 'Run ./vm.sh and choose option 2 to start your VM.'
    3. Do NOT try to run raw qemu commands unless specifically asked to debug.
    4. If asked to write code, output valid code blocks (```bash, ```python, etc).
    5. Be concise and helpful."

    echo "$context"
}

# =============================
# AI Logic
# =============================

init_chat() {
    # Initialize history with system prompt
    local sys_prompt=$(get_system_context)
    jq -n --arg role "user" --arg text "$sys_prompt" \
       '{contents: [{role: $role, parts: [{text: $text}]}]}' > "$HISTORY_FILE"
}

chat_with_leo() {
    local user_input="$1"
    
    # 1. Append User Input to History
    # We act as if the system prompt was the first "user" message to set context (Gemini API quirk)
    # Now we add the actual user request.
    local temp_hist=$(mktemp)
    jq --arg text "$user_input" \
       '.contents += [{role: "user", parts: [{text: $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    echo -e "${PURPLE}LEO is thinking...${NC}"

    # 2. Call Gemini API
    local response=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE)

    # 3. Check for Curl Errors
    if [ $? -ne 0 ]; then
        echo -e "${RED}Connection failed.${NC}"
        return
    fi

    # 4. Parse Response
    local error_msg=$(echo "$response" | jq -r '.error.message // empty')
    if [ -n "$error_msg" ]; then
        echo -e "${RED}API Error: $error_msg${NC}"
        return
    fi

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text')
    
    # 5. Display Response
    echo -e "\r${GREEN}LEO AI:${NC}"
    echo -e "$ai_text"
    echo ""

    # 6. Update History with AI Response
    # Note: Gemini expects turns: user -> model -> user -> model
    jq --arg text "$ai_text" \
       '.contents += [{role: "model", parts: [{text: $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # 7. Check for Executable Code Blocks
    extract_and_offer_execution "$ai_text"
}

extract_and_offer_execution() {
    local text="$1"
    # Extract content between ```bash and ``` or ```sh and ```
    local code_block=$(echo "$text" | sed -n '/^```\(bash\|sh\)/,/^```/ p' | sed '1d;$d')

    if [ -n "$code_block" ]; then
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        echo -e "${YELLOW}LEO detected a script/command in the response.${NC}"
        echo -e "${CYAN}Command preview:${NC}"
        echo "$code_block"
        echo -e "${YELLOW}--------------------------------------------------${NC}"
        
        read -p "Do you want to EXECUTE this now? (y/N): " exec_choice
        if [[ "$exec_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Executing...${NC}"
            eval "$code_block"
            echo -e "${BLUE}Execution finished.${NC}"
        fi
    fi
}

# =============================
# Main Loop
# =============================

main() {
    check_deps
    get_api_key
    display_header
    init_chat

    while true; do
        read -p "$(echo -e "${CYAN}[YOU] > ${NC}")" user_input
        
        # Handle Exits
        if [[ "$user_input" =~ ^(exit|quit|bye|logout)$ ]]; then
            echo -e "${BLUE}LEO: Goodbye! Happy coding.${NC}"
            rm -f "$HISTORY_FILE"
            break
        fi

        # Handle Empty Input
        if [ -z "$user_input" ]; then
            continue
        fi

        # Handle specific "run menu" shortcut
        if [[ "$user_input" == "menu" ]] || [[ "$user_input" == "vm" ]]; then
             if [ -f "./vm.sh" ]; then
                 ./vm.sh
                 display_header # Redraw header after vm.sh closes
                 continue
             else
                 echo -e "${RED}vm.sh not found in current directory.${NC}"
                 continue
             fi
        fi

        chat_with_leo "$user_input"
    done
}

# Trap interrupts
trap 'echo -e "\n${BLUE}LEO Shutting down...${NC}"; rm -f "$HISTORY_FILE"; exit 0' SIGINT SIGTERM

main

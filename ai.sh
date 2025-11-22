#!/bin/bash
# ==============================================================================
# LEO AI v2.2 - AUTONOMOUS SYSTEM AGENT
# Powered by Gemini Pro
# Fixes: Real VM Detection, Auto-Error Correction, Path Consistency
# ==============================================================================

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
API_KEY_FILE="$HOME/.leo_ai_key"
HISTORY_FILE="/tmp/leo_v2_history.json"
PLUGIN_DIR="$SCRIPT_DIR/plugins"

# === CRITICAL PATH FIX ===
# vm.sh stores VMs in $HOME/vms by default. We must match this.
VM_DIR="$HOME/vms" 

# === API CONFIGURATION ===
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
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================================
# 1. Core Logic & VM State Detection
# ==============================================================================

init_dirs() {
    mkdir -p "$PLUGIN_DIR"
    mkdir -p "$VM_DIR"
}

# Native VM Check - Does not rely on sourcing vm.sh (More stable)
get_real_vm_status() {
    local status_output=""
    if [ -d "$VM_DIR" ]; then
        # Find all .conf files
        local configs=$(find "$VM_DIR" -name "*.conf" 2>/dev/null)
        if [ -z "$configs" ]; then
            status_output="No VMs found in $VM_DIR."
        else
            for conf in $configs; do
                local vm_name=$(basename "$conf" .conf)
                # Check directly in process list
                if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
                    status_output+="- VM: $vm_name | Status: RUNNING\n"
                else
                    status_output+="- VM: $vm_name | Status: STOPPED\n"
                fi
            done
        fi
    else
        status_output="VM Directory $VM_DIR does not exist."
    fi
    echo "$status_output"
}

get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        GEMINI_API_KEY=$(cat "$API_KEY_FILE")
    else
        echo -e "${YELLOW}Setup: Enter Google Gemini API Key:${NC}"
        read -s GEMINI_API_KEY
        echo "$GEMINI_API_KEY" > "$API_KEY_FILE"
    fi
}

# ==============================================================================
# 2. System Prompt & Context
# ==============================================================================

get_system_prompt() {
    # Get Real-Time VM Status
    local vm_status=$(get_real_vm_status)
    
    local sys_context="You are LEO AI v2.2, a System Agent.
    
    USER: $(whoami) | PATH: $SCRIPT_DIR | DATE: $(date)

    *** CRITICAL: CURRENT VM STATE ***
    $vm_status
    (Trust this list. If a VM is listed as RUNNING here, it is running.)

    CAPABILITIES:
    You have DIRECT tools. Output a tool block to use them.

    TOOLS:
    1. READ_FILE <path>
    2. WRITE_FILE <path> \n <content> \n END_WRITE_FILE
       (Use this to FIX files or Self-Mod).
    3. LIST_FILES <path>
    4. EXECUTE_CMD <command>
    5. VM_ACTION <action> <vm_name>
       (Actions: START, STOP, CREATE, INFO. Creates trigger local scripts).
       
    ERROR PROTOCOL (SELF-MOD):
    If a tool fails (returns [SYSTEM_ERROR]), you MUST analyze why.
    - If a file is missing, try to create it.
    - If a script has syntax errors, READ it, fix the code, and WRITE it back.
    - Do not ask the user for permission to fix internal errors; just do it.

    Be FAST. Do not type 'Thinking'.
    "
    echo "$sys_context" | jq -Rsa .
}

init_history() {
    echo "{\"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": $(get_system_prompt)}]}]}" > "$HISTORY_FILE"
}

# ==============================================================================
# 3. UI & Animation
# ==============================================================================

type_effect() {
    local text="$1"
    echo -e "${GREEN}LEO v2:${NC}"
    # Fast python typer
    if command -v python3 &>/dev/null; then
        python3 -c "import sys, time; text='''$text'''; 
for c in text: sys.stdout.write(c); sys.stdout.flush(); time.sleep(0.003)"
        echo
    else
        echo -e "$text"
    fi
}

thinking_animation() {
    local pid=$1
    local spinstr='|/-\'
    tput civis
    echo -ne "${PURPLE}LEO v2: Thinking... ${NC}"
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    echo -ne "\r\033[K" # Clear line
    tput cnorm
}

# ==============================================================================
# 4. Tool Execution & Self-Correction Logic
# ==============================================================================

parse_and_execute_tools() {
    local input="$1"
    local tool_output=""
    local has_action=false

    # 1. LIST_FILES
    if echo "$input" | grep -q "LIST_FILES"; then
        local path=$(echo "$input" | grep "LIST_FILES" | awk '{print $2}')
        echo -e "${YELLOW}[TOOL] Listing: $path${NC}"
        if [ -d "$path" ] || [ -f "$path" ]; then
            local res=$(ls -F "$path" 2>&1)
            tool_output+="[SUCCESS] LIST_FILES $path:\n$res\n"
        else
            tool_output+="[SYSTEM_ERROR] LIST_FILES: $path not found.\n"
        fi
        has_action=true
    fi

    # 2. READ_FILE
    if echo "$input" | grep -q "READ_FILE"; then
        local path=$(echo "$input" | grep "READ_FILE" | awk '{print $2}')
        echo -e "${YELLOW}[TOOL] Reading: $path${NC}"
        if [ -f "$path" ]; then
            local res=$(cat "$path")
            tool_output+="[SUCCESS] READ_FILE $path:\n$res\n"
        else
            tool_output+="[SYSTEM_ERROR] READ_FILE: File $path does not exist. Suggest creating it.\n"
        fi
        has_action=true
    fi

    # 3. EXECUTE_CMD
    if echo "$input" | grep -q "EXECUTE_CMD"; then
        local cmd=$(echo "$input" | grep "EXECUTE_CMD" | sed 's/EXECUTE_CMD //')
        echo -e "${RED}[DANGER] LEO running: ${BOLD}$cmd${NC}"
        
        # Auto-allow if it's a simple fix command, else ask
        # For this version, we ask unless it's a system check
        local res
        if eval "$cmd" > /tmp/leo_cmd_out 2>&1; then
            res=$(cat /tmp/leo_cmd_out)
            tool_output+="[SUCCESS] EXECUTE_CMD:\n$res\n"
        else
            res=$(cat /tmp/leo_cmd_out)
            tool_output+="[SYSTEM_ERROR] EXECUTE_CMD failed:\n$res\n"
        fi
        rm -f /tmp/leo_cmd_out
        has_action=true
    fi

    # 4. WRITE_FILE
    if echo "$input" | grep -q "WRITE_FILE"; then
        local path=$(echo "$input" | grep "WRITE_FILE" | head -n1 | awk '{print $2}')
        local content=$(echo "$input" | sed -n '/WRITE_FILE/,/END_WRITE_FILE/p' | sed '1d;$d')
        
        echo -e "${RED}[MODIFY] Writing to: $path${NC}"
        mkdir -p "$(dirname "$path")"
        if echo "$content" > "$path"; then
             echo -e "${GREEN}File saved.${NC}"
             tool_output+="[SUCCESS] Written to $path.\n"
             # If fixing self
             if [[ "$path" == *"$0"* ]]; then
                 echo -e "${MAGENTA}LEO updated itself. Restarting...${NC}"
                 exec "$0"
             fi
        else
             tool_output+="[SYSTEM_ERROR] Write failed. Check permissions.\n"
        fi
        has_action=true
    fi

    # 5. VM Actions (Integration with vm.sh)
    if echo "$input" | grep -q "VM_ACTION"; then
        local action_line=$(echo "$input" | grep "VM_ACTION")
        echo -e "${YELLOW}[VM] Processing $action_line${NC}"
        
        # We assume vm.sh functions are loaded via source below
        if command -v start_vm &>/dev/null; then
             local vm_name=$(echo "$action_line" | awk '{print $3}')
             local cmd_res=""
             
             if [[ "$action_line" == *"START"* ]]; then 
                 start_vm "$vm_name" && cmd_res="Started $vm_name" || cmd_res="Failed to start $vm_name"
             elif [[ "$action_line" == *"STOP"* ]]; then 
                 stop_vm "$vm_name" && cmd_res="Stopped $vm_name" || cmd_res="Failed to stop $vm_name"
             elif [[ "$action_line" == *"CREATE"* ]]; then 
                 create_new_vm && cmd_res="Created VM"
             elif [[ "$action_line" == *"INFO"* ]]; then
                 show_vm_info "$vm_name"
                 cmd_res="Info displayed"
             fi
             tool_output+="[SUCCESS] VM_ACTION: $cmd_res\n"
        else
             tool_output+="[SYSTEM_ERROR] VM functions not loaded. Make sure vm.sh is in $SCRIPT_DIR\n"
        fi
        has_action=true
    fi

    if [ "$has_action" = true ]; then
        echo -e "${GRAY}Analyzing tool output...${NC}"
        sleep 0.5
        send_to_leo "SYSTEM_FEEDBACK:\n$tool_output\n\nINSTRUCTION: If [SYSTEM_ERROR] exists, analyze the cause and try to fix it using tools immediately. Otherwise, inform user."
    fi
}

send_to_leo() {
    local user_input="$1"
    
    # 1. Update History
    local temp_hist=$(mktemp)
    jq --arg text "$user_input" '.contents += [{"role": "user", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # 2. Call API (Background)
    local response_file=$(mktemp)
    curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE > "$response_file" &
    
    local curl_pid=$!
    thinking_animation $curl_pid
    wait $curl_pid

    local response=$(cat "$response_file")
    rm "$response_file"

    # 3. Handle API Errors
    if echo "$response" | grep -q "error"; then
        local err_msg=$(echo "$response" | jq -r '.error.message')
        echo -e "${RED}API Error: $err_msg${NC}"
        # Retry logic could go here
        return
    fi

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    if [ -z "$ai_text" ]; then
        echo -e "${RED}LEO returned no content.${NC}"
        return
    fi

    # 4. Display Output
    # Don't show internal thoughts/tool calls if they are huge, 
    # but for transparency we show the text.
    # The tool parsing happens AFTER display.
    sleep 0.2
    type_effect "$ai_text"
    echo -e "${GRAY}------------------------------------------------${NC}"

    # 5. Save AI response
    jq --arg text "$ai_text" '.contents += [{"role": "model", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # 6. Execute Tools
    parse_and_execute_tools "$ai_text"
}

# ==============================================================================
# 5. Main Execution
# ==============================================================================

display_header() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
   __    ____  ___      ___    ____ 
  |  |  |  __||   \    /   \  |    |
  |  |__|  __|| |  |  |  O  | |  | |
  |_____|____||___/    \___/  |____|
                                    
      v2.2 - AUTONOMOUS AGENT
EOF
    echo -e "${NC}"
    echo -e "System: ${BOLD}$(uname -s)${NC} | VM Dir: ${BOLD}$VM_DIR${NC}"
    echo -e "VMs Detected: ${BOLD}$(find "$VM_DIR" -name "*.conf" 2>/dev/null | wc -l)${NC}"
    echo "------------------------------------------"
}

main() {
    init_dirs
    get_api_key
    
    # Refresh context with correct VM info
    init_history
    display_header

    # Load VM functions for execution
    if [ -f "$SCRIPT_DIR/vm.sh" ]; then
         # Strip traps and main_menu execution
         sed 's/^trap/#trap/g' "$SCRIPT_DIR/vm.sh" | \
         sed 's/^main_menu/#main_menu/g' | \
         sed 's/^check_dependencies/#check_dependencies/g' > "/tmp/leo_vm_funcs.sh"
         source "/tmp/leo_vm_funcs.sh" 2>/dev/null
    fi

    while true; do
        echo -e "${BLUE}╭── [$(whoami)@LEO]${NC}"
        read -p "╰──➤ " user_input

        if [[ "$user_input" =~ ^(exit|quit|leave)$ ]]; then
            echo -e "${PURPLE}Shutting down...${NC}"
            rm -f /tmp/leo_vm_funcs.sh
            break
        fi
        
        if [ -z "$user_input" ]; then continue; fi

        # Update prompt with latest VM status silently before every message
        # This ensures if you started a VM outside LEO, LEO knows now.
        local fresh_prompt=$(get_system_prompt)
        # We replace the very first message in history (system prompt) with the fresh one
        local temp_hist=$(mktemp)
        jq --arg text "$fresh_prompt" '.contents[0].parts[0].text = $text' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

        send_to_leo "$user_input"
    done
}

trap 'rm -f /tmp/leo_v2_history.json /tmp/leo_vm_funcs.sh; echo -e "\n${RED}Force Exit.${NC}"; exit' SIGINT

main

#!/bin/bash
# ==============================================================================
# LEO AI v2.4 - AUTONOMOUS AGENT
# Powered by Gemini Pro
# Fixes: STRICT BLOCKING (No overlap), Synchronous API, VM Context
# ==============================================================================

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
API_KEY_FILE="$HOME/.leo_ai_key"
HISTORY_FILE="/tmp/leo_v2_history.json"
PLUGIN_DIR="$SCRIPT_DIR/plugins"
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
# 1. Core Logic & State
# ==============================================================================

init_dirs() {
    mkdir -p "$PLUGIN_DIR"
    mkdir -p "$VM_DIR"
}

get_real_vm_status() {
    local status_output=""
    if [ -d "$VM_DIR" ]; then
        local configs=$(find "$VM_DIR" -name "*.conf" 2>/dev/null)
        if [ -z "$configs" ]; then
            status_output="No VMs found in $VM_DIR."
        else
            for conf in $configs; do
                local vm_name=$(basename "$conf" .conf)
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

get_system_prompt() {
    local vm_status=$(get_real_vm_status)
    # We explicitly tell it NOT to use virsh, but to use VM_ACTION or just trust the status.
    local sys_context="You are LEO AI v2.4.
    USER: $(whoami) | PATH: $SCRIPT_DIR
    
    *** REAL-TIME VM STATUS (TRUST THIS) ***
    $vm_status

    TOOLS (Output strictly formatted block):
    1. READ_FILE <path>
    2. WRITE_FILE <path> \n <content> \n END_WRITE_FILE
    3. LIST_FILES <path>
    4. EXECUTE_CMD <command>
    5. VM_ACTION <action> <vm_name>
       (Use this for VM control. Do NOT use virsh.)

    PROTOCOL:
    - If tool fails [SYSTEM_ERROR], FIX IT.
    - Do not type 'Thinking'.
    "
    echo "$sys_context" | jq -Rsa .
}

init_history() {
    echo "{\"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": $(get_system_prompt)}]}]}" > "$HISTORY_FILE"
}

# ==============================================================================
# 2. UI & Animation (Strictly Synchronous)
# ==============================================================================

type_effect() {
    local text="$1"
    echo -e "${GREEN}LEO v2:${NC}"
    # Standard echo is faster and safer for blocking issues
    echo -e "$text"
}

# Run animation in background, store PID, return it
start_spinner() {
    (
        local spinstr='|/-\'
        tput civis
        while true; do
            local temp=${spinstr#?}
            printf "${PURPLE}Thinking... [%c]${NC}" "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep 0.1
            printf "\r\033[K"
        done
    ) &
    echo $!
}

stop_spinner() {
    local pid=$1
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    tput cnorm
    printf "\r\033[K" # Clean line
}

# ==============================================================================
# 3. Tool Execution
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
            tool_output+="[SYSTEM_ERROR] READ_FILE: File $path does not exist.\n"
        fi
        has_action=true
    fi

    # 3. EXECUTE_CMD
    if echo "$input" | grep -q "EXECUTE_CMD"; then
        # Cleaner regex to remove the command prefix
        local cmd=$(echo "$input" | sed 's/.*EXECUTE_CMD //')
        echo -e "${RED}[DANGER] LEO running: ${BOLD}$cmd${NC}"
        
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
             tool_output+="[SUCCESS] Written to $path.\n"
             if [[ "$path" == *"$0"* ]]; then
                 echo -e "${MAGENTA}LEO updated itself. Restarting...${NC}"
                 exec "$0"
             fi
        else
             tool_output+="[SYSTEM_ERROR] Write failed.\n"
        fi
        has_action=true
    fi

    # 5. VM Actions
    if echo "$input" | grep -q "VM_ACTION"; then
        local action_line=$(echo "$input" | grep "VM_ACTION")
        echo -e "${YELLOW}[VM] Processing $action_line${NC}"
        
        if command -v start_vm &>/dev/null; then
             local vm_name=$(echo "$action_line" | awk '{print $3}')
             local cmd_res=""
             if [[ "$action_line" == *"START"* ]]; then 
                 start_vm "$vm_name" && cmd_res="Started" || cmd_res="Failed"
             elif [[ "$action_line" == *"STOP"* ]]; then 
                 stop_vm "$vm_name" && cmd_res="Stopped" || cmd_res="Failed"
             elif [[ "$action_line" == *"CREATE"* ]]; then 
                 create_new_vm && cmd_res="Created"
             elif [[ "$action_line" == *"INFO"* ]]; then
                 show_vm_info "$vm_name"
                 cmd_res="Info shown"
             fi
             tool_output+="[SUCCESS] $cmd_res\n"
        else
             tool_output+="[SYSTEM_ERROR] VM functions not loaded.\n"
        fi
        has_action=true
    fi

    if [ "$has_action" = true ]; then
        echo -e "${GRAY}Analyzing results...${NC}"
        # RECURSIVE CALL: Block until this finishes
        send_to_leo "SYSTEM_FEEDBACK:\n$tool_output\n\nINSTRUCTION: Analyze output. If error, fix it. If success, inform user."
    fi
}

send_to_leo() {
    local user_input="$1"
    
    # 1. Update History
    local temp_hist=$(mktemp)
    jq --arg text "$user_input" '.contents += [{"role": "user", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # 2. Start Animation (Background)
    local spinner_pid=$(start_spinner)

    # 3. Call API (SYNCHRONOUS / BLOCKING)
    # The script STOPS here until curl finishes. You cannot type.
    local response_file=$(mktemp)
    curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE > "$response_file"
    
    # 4. Stop Animation
    stop_spinner $spinner_pid

    local response=$(cat "$response_file")
    rm "$response_file"

    # 5. Error Checking
    if echo "$response" | grep -q "error"; then
        echo -e "${RED}API Error: $(echo "$response" | jq -r '.error.message')${NC}"
        return
    fi

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    if [ -z "$ai_text" ]; then
        echo -e "${RED}[DEBUG] Empty Response. Raw Output:${NC}"
        echo "$response" | head -n 5
        return
    fi

    # 6. Output
    type_effect "$ai_text"
    echo -e "${GRAY}------------------------------------------------${NC}"

    # 7. Update History
    jq --arg text "$ai_text" '.contents += [{"role": "model", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # 8. Execute Tools (Blocks until done)
    parse_and_execute_tools "$ai_text"
}

# ==============================================================================
# 4. Main Execution
# ==============================================================================

display_header() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
   __    ____  ___      ___    ____ 
  |  |  |  __||   \    /   \  |    |
  |  |__|  __|| |  |  |  O  | |  | |
  |_____|____||___/    \___/  |____|
                                    
      v2.4 - STRICT BLOCKING MODE
EOF
    echo -e "${NC}"
    echo -e "System: ${BOLD}$(uname -s)${NC} | VM Dir: ${BOLD}$VM_DIR${NC}"
    echo "------------------------------------------"
}

main() {
    init_dirs
    get_api_key
    init_history
    display_header

    # Load VM functions
    if [ -f "$SCRIPT_DIR/vm.sh" ]; then
         sed 's/^trap/#trap/g' "$SCRIPT_DIR/vm.sh" | \
         sed 's/^main_menu/#main_menu/g' | \
         sed 's/^check_dependencies/#check_dependencies/g' > "/tmp/leo_vm_funcs.sh"
         source "/tmp/leo_vm_funcs.sh" 2>/dev/null
    fi

    while true; do
        echo -e "${BLUE}╭── [$(whoami)@LEO]${NC}"
        
        # The prompt only appears when the previous command chain is DEAD.
        read -p "╰──➤ " user_input

        if [[ "$user_input" =~ ^(exit|quit|leave)$ ]]; then
            echo -e "${PURPLE}Shutting down...${NC}"
            rm -f /tmp/leo_vm_funcs.sh
            break
        fi
        
        if [ -z "$user_input" ]; then continue; fi

        # Refresh VM status context before sending
        local fresh_prompt=$(get_system_prompt)
        local temp_hist=$(mktemp)
        jq --arg text "$fresh_prompt" '.contents[0].parts[0].text = $text' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

        send_to_leo "$user_input"
    done
}

trap 'rm -f /tmp/leo_v2_history.json /tmp/leo_vm_funcs.sh; echo -e "\n${RED}Force Exit.${NC}"; exit' SIGINT

main

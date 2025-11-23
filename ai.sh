#!/bin/bash
# ==============================================================================
# LEO AI v3.0 - ULTIMATE AUTONOMOUS AGENT
# Powered by Gemini 2.5 Pro | API v1
# Capabilities: Full FS Access, Real VM Integration, Deep Context
# ==============================================================================

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
API_KEY_FILE="$HOME/.leo_ai_key"
HISTORY_FILE="/tmp/leo_v3_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"

# === USER CONFIGURATION ===
# User requested gemini-2.5-pro (Ensure your API key has access to this model)
MODEL="gemini-2.5-pro"
# User requested v1 endpoint
API_URL="https://generativelanguage.googleapis.com/v1/models"

# Directories to manage
TARGET_DIRS="$SCRIPT_DIR/isam $SCRIPT_DIR/LEO-VM"
PLUGIN_DIR="$SCRIPT_DIR/plugins"

# --- Colors & UI ---
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
# 1. System Initialization & Deep Knowledge Ingestion
# ==============================================================================

init_system() {
    mkdir -p "$SCRIPT_DIR/isam" "$SCRIPT_DIR/LEO-VM" "$PLUGIN_DIR"
    touch "$MEMORY_FILE"
}

get_time() {
    date +"%H:%M:%S"
}

get_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        GEMINI_API_KEY=$(cat "$API_KEY_FILE")
    else
        clear
        echo -e "${YELLOW}LEO AI v3 Setup${NC}"
        echo -e "Please enter your Google Gemini API Key:"
        read -s GEMINI_API_KEY
        if [ -z "$GEMINI_API_KEY" ]; then echo "API Key required."; exit 1; fi
        echo "$GEMINI_API_KEY" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
    fi
}

# This gives the AI "Real Knowledge" of your VM script
ingest_vm_knowledge() {
    local vm_script="$SCRIPT_DIR/vm.sh"
    local knowledge=""
    
    if [ -f "$vm_script" ]; then
        # Extract function names from vm.sh
        local funcs=$(grep "^[a-zA-Z0-9_]\+()" "$vm_script" | sed 's/()//g' | tr '\n' ', ')
        knowledge="VM MANAGER SCRIPT (vm.sh) FOUND.\n"
        knowledge+="Available Functions: $funcs\n"
        knowledge+="You can execute these by writing a script that sources vm.sh or calling ./vm.sh."
    else
        knowledge="vm.sh NOT FOUND. VM management capabilities limited."
    fi
    echo "$knowledge"
}

# This gives the AI "Real Knowledge" of the file system
ingest_file_structure() {
    local struct=""
    for d in $TARGET_DIRS; do
        if [ -d "$d" ]; then
            struct+="Directory $d:\n"
            struct+=$(ls -R "$d" 2>/dev/null | head -n 20) # Limit context size
            struct+="\n"
        fi
    done
    echo "$struct"
}

# ==============================================================================
# 2. The Brain (Context & Prompting)
# ==============================================================================

get_system_prompt() {
    local vm_knowledge=$(ingest_vm_knowledge)
    local fs_knowledge=$(ingest_file_structure)
    local memory=$(cat "$MEMORY_FILE")
    
    local sys_context="You are LEO AI v3, an Autonomous System Administrator.
    
    *** REAL-TIME CONTEXT ***
    Time: $(date)
    User: $(whoami)
    Current Dir: $SCRIPT_DIR
    
    *** SYSTEM KNOWLEDGE ***
    $vm_knowledge
    
    *** FILE SYSTEM OVERVIEW ***
    $fs_knowledge
    
    *** LONG TERM MEMORY ***
    $memory

    *** TOOLS & CAPABILITIES ***
    You are an AGENT. To help the user, you MUST use tools.
    Output strictly in this format to use a tool:
    
    TOOL: <TOOL_NAME> <ARGUMENTS>
    
    Available Tools:
    1. READ_FILE <path>           (Read file content)
    2. WRITE_FILE <path>          (Create/Overwrite file - Content goes on next lines, end with END_WRITE)
    3. EXEC_CMD <command>         (Run Bash command - CAUTION)
    4. SEARCH_WEB <query>         (Search internet)
    5. MEMORY_SAVE <text>         (Save a fact for later)
    
    *** RULES ***
    1. Do not use markdown for tool commands.
    2. If fixing ai.sh, be extremely careful with JSON syntax.
    3. To Manage VMs: Use EXEC_CMD to call './vm.sh' or source it.
    4. Be concise.
    "
    # Escape for JSON
    echo "$sys_context" | jq -Rsa .
}

init_history() {
    echo "{\"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": $(get_system_prompt)}]}]}" > "$HISTORY_FILE"
}

# ==============================================================================
# 3. UI Components (The "Best Timing" & "Better UI")
# ==============================================================================

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    # Hide cursor
    tput civis
    
    echo -ne "${PURPLE}   LEO is Thinking... "
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    
    # Show cursor
    tput cnorm
    echo -ne "${NC}"
}

print_ai_msg() {
    local msg="$1"
    echo -e "\r${CYAN}┌── [LEO AI] [$(get_time)]${NC}"
    echo -e "${CYAN}│${NC} $msg"
    echo -e "${CYAN}└──────────────────────────────────────────${NC}"
}

print_user_msg() {
    echo -e "\n${GREEN}┌── [YOU] [$(get_time)]${NC}"
}

# ==============================================================================
# 4. Tool Execution Engine
# ==============================================================================

execute_tool() {
    local tool_line="$1"
    local full_response="$2" # Needed for multi-line WRITE_FILE
    local output=""
    local has_action=false

    # --- READ_FILE ---
    if [[ "$tool_line" == TOOL:\ READ_FILE* ]]; then
        local path=$(echo "$tool_line" | cut -d' ' -f3-)
        echo -e "${YELLOW}   >>> Reading: $path${NC}"
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
        echo -e "${RED}   >>> Executing: $cmd${NC}"
        # Automatic safety check? For now, we trust the user since they requested "Real Knowledge"
        local cmd_out=$(eval "$cmd" 2>&1)
        output="COMMAND OUTPUT:\n$cmd_out"
        has_action=true
    fi

    # --- WRITE_FILE ---
    if [[ "$tool_line" == TOOL:\ WRITE_FILE* ]]; then
        local path=$(echo "$tool_line" | cut -d' ' -f3-)
        # Extract content: Look for lines between the TOOL line and END_WRITE
        local content=$(echo "$full_response" | sed -n "/TOOL: WRITE_FILE/,/END_WRITE/p" | sed '1d;$d')
        
        echo -e "${YELLOW}   >>> Writing to: $path${NC}"
        mkdir -p "$(dirname "$path")"
        echo "$content" > "$path"
        output="SUCCESS: File $path written."
        
        # Self-Correction: If editing ai.sh, warn user
        if [[ "$path" == *"ai.sh"* ]]; then
            echo -e "${RED}   !!! LEO MODIFIED ITSELF. RESTART ADVISED. !!!${NC}"
        fi
        has_action=true
    fi

    # --- MEMORY_SAVE ---
    if [[ "$tool_line" == TOOL:\ MEMORY_SAVE* ]]; then
        local fact=$(echo "$tool_line" | cut -d' ' -f3-)
        echo "$fact" >> "$MEMORY_FILE"
        echo -e "${GRAY}   >>> Memory Saved.${NC}"
        output="Memory updated."
        has_action=true
    fi

    # --- SEARCH_WEB ---
    if [[ "$tool_line" == TOOL:\ SEARCH_WEB* ]]; then
        local query=$(echo "$tool_line" | cut -d' ' -f3-)
        echo -e "${BLUE}   >>> Searching Web: $query${NC}"
        # Mocking web search for stability without external deps like ddgr, 
        # unless you have a search API key. 
        # For real implementation, verify 'ddgr' exists:
        if command -v ddgr &> /dev/null; then
            output=$(ddgr --json -n 3 "$query" 2>&1)
        else
            output="ERROR: 'ddgr' tool not installed. Cannot search web."
        fi
        has_action=true
    fi

    # Return result if action was taken
    if [ "$has_action" = true ]; then
        # Feedback loop: Send the tool output back to LEO
        send_to_leo "SYSTEM_TOOL_OUTPUT:\n$output" "tool_feedback"
    fi
}

# ==============================================================================
# 5. Communication Core
# ==============================================================================

send_to_leo() {
    local input="$1"
    local mode="$2" # "user" or "tool_feedback"
    
    # Update History
    local temp_hist=$(mktemp)
    local role="user"
    # If it's tool output, we treat it as user input (system info)
    jq --arg text "$input" --arg role "$role" \
       '.contents += [{"role": $role, "parts": [{"text": $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # API Request (Backgrounded for spinner)
    local response_file=$(mktemp)
    
    # Using v1 endpoint as requested
    curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE > "$response_file" &
        
    local curl_pid=$!
    
    # Only show spinner if it's a user interaction, distinct visual for tool loops
    if [ "$mode" != "tool_feedback" ]; then
        echo ""
        spinner $curl_pid
        echo ""
    else
        wait $curl_pid
    fi

    # Read Response
    local raw_response=$(cat "$response_file")
    rm "$response_file"

    # Error Handling
    if echo "$raw_response" | grep -q "error"; then
        local err_msg=$(echo "$raw_response" | jq -r '.error.message')
        echo -e "${RED}API Error ($MODEL): $err_msg${NC}"
        return
    fi

    # Extract Text
    local ai_text=$(echo "$raw_response" | jq -r '.candidates[0].content.parts[0].text // empty')

    if [ -z "$ai_text" ]; then
        echo -e "${RED}LEO returned empty response.${NC}"
        return
    fi

    # Update History with AI reply
    jq --arg text "$ai_text" \
       '.contents += [{"role": "model", "parts": [{"text": $text}]}]' \
       "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # Display Output (Clean output, remove Tool commands from visual if desired, 
    # but here we show them for "Real Knowledge" proof)
    print_ai_msg "$ai_text"

    # Parse Tools
    # We grep for lines starting with TOOL:
    while read -r line; do
        if [[ "$line" == TOOL:* ]]; then
            execute_tool "$line" "$ai_text"
        fi
    done <<< "$ai_text"
}

# ==============================================================================
# 6. Main Application Loop
# ==============================================================================

display_header() {
    clear
    cat << "EOF"
 _      _____ ____    ___  _ 
| |    | ____/ __ \  /   || |
| |    |  __| |  | || | || |
| |___ | |__| |__| || | || |
|_____||_____\____/  \___/|_| v3.0
EOF
    echo -e "${CYAN}Powered by $MODEL (v1)${NC}"
    echo -e "${GRAY}Filesystem Access: ENABLED | VM Knowledge: ACTIVE${NC}"
    echo "---------------------------------------------------"
}

main() {
    init_system
    get_api_key
    init_history # Loads system prompt with real VM knowledge
    display_header

    while true; do
        # UI: User prompt
        print_user_msg
        
        # This read -p is the "Typing Box". 
        # It is BLOCKING. It will NOT appear until the previous loop (AI response) is fully done.
        read -p "╰──➤ " user_input

        # Logic: Real Exit
        if [[ "$user_input" =~ ^(exit|quit|bye|leave)$ ]]; then
            echo -e "${PURPLE}LEO: Shutting down systems. Goodbye.${NC}"
            break
        fi
        
        if [ -z "$user_input" ]; then continue; fi

        # Send to AI
        send_to_leo "$user_input" "user"
    done
}

# Cleanup Trap
trap 'rm -f /tmp/leo_v3_history.json; echo -e "\n${RED}Interrupted.${NC}"; exit' SIGINT

# Start
main

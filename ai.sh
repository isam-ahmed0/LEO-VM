#!/bin/bash
# ==============================================================================
# LEO AI v2.0 - AUTOMOUS AGENT
# Powered by Gemini Pro
# Capabilities: Filesystem Access, Self-Mod, Web, Plugins, VM Management
# ==============================================================================

# --- Configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
API_KEY_FILE="$HOME/.leo_ai_key"
HISTORY_FILE="/tmp/leo_v2_history.json"
MEMORY_FILE="$HOME/.leo_memory.txt"
PLUGIN_DIR="$SCRIPT_DIR/plugins"
TARGET_DIRS="$SCRIPT_DIR/isam $SCRIPT_DIR/LEO-VM"

# === UPDATED CONFIGURATION ===
MODEL="gemini-2.5-pro"
# Using v1 endpoint as requested
API_URL="https://generativelanguage.googleapis.com/v1/models"

# Colors & Styling
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
# 1. Initialization & Plugin Loader
# ==============================================================================

init_dirs() {
    mkdir -p "$PLUGIN_DIR"
    mkdir -p "$SCRIPT_DIR/isam"
    mkdir -p "$SCRIPT_DIR/LEO-VM"
}

load_plugins() {
    PLUGIN_CONTEXT=""
    if [ -d "$PLUGIN_DIR" ]; then
        for plugin in "$PLUGIN_DIR"/*.sh; do
            if [ -f "$plugin" ]; then
                source "$plugin"
                local p_name=$(basename "$plugin")
                PLUGIN_CONTEXT+="- Plugin Loaded: $p_name\n"
            fi
        done
    fi
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
# 2. The "Brain" - Prompt Engineering
# ==============================================================================

get_system_prompt() {
    local sys_context="You are LEO AI v2, an Autonomous System Administrator Agent.
    
    USER DETAILS:
    - User: $(whoami)
    - Directory: $SCRIPT_DIR
    - Date: $(date)

    CAPABILITIES & TOOLS:
    You are not just a chatbot. You have DIRECT access to the system via TOOLS.
    To perform an action, you MUST output a strictly formatted tool block.

    AVAILABLE TOOLS:
    
    1. READ_FILE <path>
       - Read contents of any file in isam/, LEO-VM/, or the current directory.
    
    2. WRITE_FILE <path>
       <content>
       END_WRITE_FILE
       - Create or Overwrite a file. Used for scripting, fixing config, or SELF-MODIFICATION.
    
    3. LIST_FILES <path>
       - List files in a directory.
    
    4. EXECUTE_CMD <command>
       - Run a bash command. Use with caution.
    
    5. WEB_SEARCH <query>
       - Search the web for real-time information.
    
    6. VM_ACTION <action> <vm_name>
       - Actions: START, STOP, CREATE, INFO, EDIT.
       
    RULES:
    1. If the user asks to fix a file, READ it first, then WRITE it back with fixes.
    2. If the user asks to fix 'ai.sh' (yourself), be extremely careful not to break JSON syntax.
    3. To run a plugin, just use EXECUTE_CMD if it's a script, or call its function.
    4. Always 'Thinking' is automatic, do not type 'Thinking...'.
    5. Be FAST and concise.

    LOADED PLUGINS:
    $PLUGIN_CONTEXT
    "
    echo "$sys_context" | jq -Rsa .
}

init_history() {
    echo "{\"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": $(get_system_prompt)}]}]}" > "$HISTORY_FILE"
}

# ==============================================================================
# 3. Tool Logic ( The Hands )
# ==============================================================================

# Spinner Animation
thinking_animation() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -ne "${PURPLE}LEO is Thinking... "
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    echo -ne "${NC}"
}

perform_web_search() {
    local query="$1"
    echo -e "${CYAN}[WEB] Searching: $query${NC}"
    
    # Try using 'ddgr' (DuckDuckGo CLI) if available
    if command -v ddgr &> /dev/null; then
        ddgr --json -n 3 "$query" 2>/dev/null
    else
        # Fallback to simple curl (limited) or mock
        echo "Web search tool 'ddgr' not found. Using basic fallback."
        echo "Results for $query: (Please install ddgr for real results)"
    fi
}

# ==============================================================================
# 4. The Agent Loop
# ==============================================================================

parse_and_execute_tools() {
    local input="$1"
    local tool_output=""
    local has_action=false

    # 1. LIST_FILES
    if echo "$input" | grep -q "LIST_FILES"; then
        local path=$(echo "$input" | grep "LIST_FILES" | awk '{print $2}')
        echo -e "${YELLOW}[TOOL] Listing: $path${NC}"
        local res=$(ls -F "$path" 2>&1)
        tool_output+="Output of LIST_FILES $path:\n$res\n"
        has_action=true
    fi

    # 2. READ_FILE
    if echo "$input" | grep -q "READ_FILE"; then
        local path=$(echo "$input" | grep "READ_FILE" | awk '{print $2}')
        echo -e "${YELLOW}[TOOL] Reading: $path${NC}"
        if [ -f "$path" ]; then
            local res=$(cat "$path")
            tool_output+="Output of READ_FILE $path:\n$res\n"
        else
            tool_output+="Error: File $path not found.\n"
        fi
        has_action=true
    fi

    # 3. EXECUTE_CMD
    if echo "$input" | grep -q "EXECUTE_CMD"; then
        local cmd=$(echo "$input" | grep "EXECUTE_CMD" | sed 's/EXECUTE_CMD //')
        echo -e "${RED}[DANGER] LEO wants to run: ${BOLD}$cmd${NC}"
        read -p "Allow? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            local res=$(eval "$cmd" 2>&1)
            tool_output+="Output of EXECUTE_CMD:\n$res\n"
        else
            tool_output+="User denied execution.\n"
        fi
        has_action=true
    fi

    # 4. WRITE_FILE (Multi-line parsing)
    if echo "$input" | grep -q "WRITE_FILE"; then
        # Extract content between WRITE_FILE and END_WRITE_FILE
        local path=$(echo "$input" | grep "WRITE_FILE" | head -n1 | awk '{print $2}')
        local content=$(echo "$input" | sed -n '/WRITE_FILE/,/END_WRITE_FILE/p' | sed '1d;$d')
        
        echo -e "${RED}[MODIFY] LEO wants to write to: $path${NC}"
        read -p "Allow? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            # Ensure directory exists
            mkdir -p "$(dirname "$path")"
            echo "$content" > "$path"
            echo -e "${GREEN}File written successfully.${NC}"
            tool_output+="Successfully wrote to $path\n"
            
            # If fixing self, re-source
            if [[ "$path" == *"$0"* ]]; then
                echo -e "${MAGENTA}LEO updated itself. Restarting...${NC}"
                exec "$0"
            fi
        else
            tool_output+="User denied write.\n"
        fi
        has_action=true
    fi

    # 5. WEB_SEARCH
    if echo "$input" | grep -q "WEB_SEARCH"; then
        local query=$(echo "$input" | grep "WEB_SEARCH" | sed 's/WEB_SEARCH //')
        local res=$(perform_web_search "$query")
        tool_output+="Web Search Results:\n$res\n"
        has_action=true
    fi

    # 6. VM Actions
    if echo "$input" | grep -q "VM_ACTION"; then
        local action_line=$(echo "$input" | grep "VM_ACTION")
        echo -e "${YELLOW}[VM] Executing $action_line${NC}"
        # Trigger EXECUTE_CMD logic implicitly or handle directly if safe
        tool_output+="VM Action Logged.\n"
        has_action=true
    fi

    if [ "$has_action" = true ]; then
        # Recursively feed output back to LEO
        echo -e "${GRAY}Sending Tool Output back to LEO...${NC}"
        send_to_leo "Tool execution results:\n$tool_output\nAnalyze these results and continue."
    fi
}

send_to_leo() {
    local user_input="$1"
    
    # Append User Input
    local temp_hist=$(mktemp)
    jq --arg text "$user_input" '.contents += [{"role": "user", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # Call API in background to allow animation
    local response_file=$(mktemp)
    
    # Updated to use v1 URL and gemini-2.5-pro
    curl -s -X POST "$API_URL/$MODEL:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d @$HISTORY_FILE > "$response_file" &
    
    local curl_pid=$!
    thinking_animation $curl_pid
    wait $curl_pid

    local response=$(cat "$response_file")
    rm "$response_file"

    # Check Error
    if echo "$response" | grep -q "error"; then
        echo -e "${RED}API Error: $(echo "$response" | jq -r '.error.message')${NC}"
        # Fallback hint if 2.5 is not found
        if echo "$response" | grep -q "404"; then
            echo -e "${YELLOW}Hint: 'gemini-2.5-pro' might not be available on your key yet. Try 'gemini-1.5-pro'.${NC}"
        fi
        return
    fi

    local ai_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    # Display AI Response
    echo -e "\r${GREEN}LEO v2:${NC}"
    echo -e "$ai_text"
    echo -e "${GRAY}------------------------------------------------${NC}"

    # Append Model Response to History
    jq --arg text "$ai_text" '.contents += [{"role": "model", "parts": [{"text": $text}]}]' "$HISTORY_FILE" > "$temp_hist" && mv "$temp_hist" "$HISTORY_FILE"

    # Check for tools in the response
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
                                    
      v2.0 - AUTONOMOUS AGENT
EOF
    echo -e "${NC}"
    echo -e "System: ${BOLD}$(uname -s)${NC} | Plugins: ${BOLD}$(ls "$PLUGIN_DIR" 2>/dev/null | wc -l)${NC}"
    echo -e "Watching: ${BOLD}isam/, LEO-VM/${NC}"
    echo "------------------------------------------"
}

main() {
    init_dirs
    get_api_key
    load_plugins
    init_history
    display_header

    # Load VM functions if present (Integration)
    if [ -f "$SCRIPT_DIR/vm.sh" ]; then
         # Simple surgery to allow calling functions via EXECUTE_CMD
         sed 's/^trap/#trap/g' "$SCRIPT_DIR/vm.sh" > "/tmp/leo_vm_funcs.sh"
         source "/tmp/leo_vm_funcs.sh" 2>/dev/null
    fi

    while true; do
        echo -e "${BLUE}╭── [$(whoami)@LEO]${NC}"
        read -p "╰──➤ " user_input

        if [[ "$user_input" =~ ^(exit|quit|leave)$ ]]; then
            echo -e "${PURPLE}Saving memory and shutting down...${NC}"
            break
        fi
        
        if [ -z "$user_input" ]; then continue; fi

        send_to_leo "$user_input"
    done
}

# Trap for cleanup
trap 'rm -f /tmp/leo_v2_history.json; echo -e "\n${RED}Force Exit.${NC}"; exit' SIGINT

main

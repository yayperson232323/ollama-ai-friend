#!/bin/bash

# AI Friend Chatbot with Ollama
# Stores memories in ~/.friend/ directory with 4 memory files
# Usage: ./friend.sh

set -e

FRIEND_DIR="$HOME/.friend"
EVENTS_FILE="$FRIEND_DIR/events.txt"
USER_FILE="$FRIEND_DIR/user.txt"
BOT_FILE="$FRIEND_DIR/bot.txt"
MISC_FILE="$FRIEND_DIR/misc.txt"

# Initialize memory directory and files
init_memory() {
    if [[ ! -d "$FRIEND_DIR" ]]; then
        mkdir -p "$FRIEND_DIR"
        touch "$EVENTS_FILE" "$USER_FILE" "$BOT_FILE" "$MISC_FILE"
        echo "Initialized memory at $FRIEND_DIR"
    fi
}

# Parse and compress memory files to reduce token usage
# Keeps important info, summarizes old data
compress_memory() {
    local file="$1"
    local max_lines=50
    
    if [[ ! -f "$file" ]]; then
        return
    fi
    
    local line_count=$(wc -l < "$file")
    
    if [[ $line_count -gt $max_lines ]]; then
        # Keep only the last max_lines entries
        tail -n "$max_lines" "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    fi
}

# Add event to memory (high priority)
add_event() {
    local event="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $event" >> "$EVENTS_FILE"
    compress_memory "$EVENTS_FILE"
}

# Add user info (important context)
add_user_info() {
    local info="$1"
    echo "$info" >> "$USER_FILE"
    compress_memory "$USER_FILE"
}

# Add bot memory (self-knowledge, preferences)
add_bot_memory() {
    local memory="$1"
    echo "$memory" >> "$BOT_FILE"
    compress_memory "$BOT_FILE"
}

# Add miscellaneous notes
add_misc() {
    local note="$1"
    echo "$note" >> "$MISC_FILE"
    compress_memory "$MISC_FILE"
}

# Build context from memory files for the prompt
build_context() {
    local context=""
    
    # Prioritize events and user info
    if [[ -f "$EVENTS_FILE" ]] && [[ -s "$EVENTS_FILE" ]]; then
        context+="Recent events:\n$(tail -n 10 "$EVENTS_FILE")\n\n"
    fi
    
    if [[ -f "$USER_FILE" ]] && [[ -s "$USER_FILE" ]]; then
        context+="User info:\n$(tail -n 5 "$USER_FILE")\n\n"
    fi
    
    if [[ -f "$BOT_FILE" ]] && [[ -s "$BOT_FILE" ]]; then
        context+="My memories:\n$(tail -n 5 "$BOT_FILE")\n\n"
    fi
    
    if [[ -f "$MISC_FILE" ]] && [[ -s "$MISC_FILE" ]]; then
        context+="Notes:\n$(tail -n 3 "$MISC_FILE")\n"
    fi
    
    echo -e "$context"
}

# Call Ollama with context
query_ollama() {
    local user_input="$1"
    local context=$(build_context)
    
    local prompt="You are a helpful AI friend. Be warm, remember the user, and keep responses concise.

Context from memories:
$context

User says: $user_input

Respond as a friend:"
    
    # Send to ollama (using default model 'mistral', change if needed)
    local response=$(echo "$prompt" | ollama run mistral)
    
    echo "$response"
}

# Main chat loop
main() {
    init_memory
    
    echo "🤖 AI Friend initialized! (memories stored at $FRIEND_DIR)"
    echo "Commands: 'exit' to quit, 'memory' to view memories, 'clear' to reset"
    echo ""
    
    while true; do
        read -p "You: " user_input
        
        # Handle special commands
        case "$user_input" in
            exit|quit)
                echo "Goodbye! 👋"
                break
                ;;
            memory)
                echo -e "\n=== MEMORIES ===\n$(build_context)\n"
                continue
                ;;
            clear)
                rm -f "$EVENTS_FILE" "$USER_FILE" "$BOT_FILE" "$MISC_FILE"
                touch "$EVENTS_FILE" "$USER_FILE" "$BOT_FILE" "$MISC_FILE"
                echo "Memories cleared!"
                continue
                ;;
        esac
        
        if [[ -z "$user_input" ]]; then
            continue
        fi
        
        # Log user input as event
        add_event "User: $user_input"
        
        # Get response from Ollama
        echo ""
        response=$(query_ollama "$user_input")
        echo "Friend: $response"
        echo ""
        
        # Log bot response and extract key info
        add_bot_memory "Responded to: $user_input"
        
        # Try to extract and store important user info if mentioned
        if echo "$user_input" | grep -iq "my name"; then
            add_user_info "User mentioned their name: $user_input"
        fi
        if echo "$user_input" | grep -iq "i like\|i love\|i hate"; then
            add_user_info "User preference: $user_input"
        fi
    done
}

main "$@"

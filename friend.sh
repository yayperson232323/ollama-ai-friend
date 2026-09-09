#!/bin/bash

# AI Friend Chatbot with Ollama
# Stores memories and transcript in ~/.friend/
# Uses gemma2:2b to filter important memories
# Usage: ./friend.sh

set -e

FRIEND_DIR="$HOME/.friend"
MEMORY_FILE="$FRIEND_DIR/memory.txt"
TRANSCRIPT_FILE="$FRIEND_DIR/transcript.txt"
TURN_COUNT_FILE="$FRIEND_DIR/turn_count.txt"

MAIN_MODEL="mistral"  # Main conversation model
FILTER_MODEL="gemma2:2b"  # Small model for memory filtering
TRANSCRIPT_LINES=10  # Keep last 5 messages (2 lines per message)
UPDATE_INTERVAL=5  # Update memory every 5 turns

# Initialize memory directory and files
init_memory() {
    if [[ ! -d "$FRIEND_DIR" ]]; then
        mkdir -p "$FRIEND_DIR"
    fi
    
    if [[ ! -f "$MEMORY_FILE" ]]; then
        touch "$MEMORY_FILE"
    fi
    
    if [[ ! -f "$TRANSCRIPT_FILE" ]]; then
        touch "$TRANSCRIPT_FILE"
    fi
    
    if [[ ! -f "$TURN_COUNT_FILE" ]]; then
        echo "0" > "$TURN_COUNT_FILE"
    fi
    
    echo "Initialized memory at $FRIEND_DIR"
}

# Get last N lines from transcript
get_recent_transcript() {
    if [[ -f "$TRANSCRIPT_FILE" ]] && [[ -s "$TRANSCRIPT_FILE" ]]; then
        tail -n "$TRANSCRIPT_LINES" "$TRANSCRIPT_FILE"
    fi
}

# Add to transcript and keep it trimmed
add_to_transcript() {
    local line="$1"
    echo "$line" >> "$TRANSCRIPT_FILE"
    
    # Keep only last N lines
    local total_lines=$(wc -l < "$TRANSCRIPT_FILE")
    if [[ $total_lines -gt $TRANSCRIPT_LINES ]]; then
        tail -n "$TRANSCRIPT_LINES" "$TRANSCRIPT_FILE" > "$TRANSCRIPT_FILE.tmp"
        mv "$TRANSCRIPT_FILE.tmp" "$TRANSCRIPT_FILE"
    fi
}

# Use small model to filter and update memory
update_memory() {
    local user_input="$1"
    local bot_response="$2"
    
    if [[ ! -f "$MEMORY_FILE" ]]; then
        touch "$MEMORY_FILE"
    fi
    
    # Get current memory
    local current_memory=$(cat "$MEMORY_FILE" 2>/dev/null || echo "")
    
    # Build filtering prompt
    local filter_prompt="You are a memory manager. Analyze this conversation and decide if anything is important to remember about the user or context.

Current memories:
$current_memory

Recent conversation:
User: $user_input
AI: $bot_response

Decide: What facts are worth remembering? Be concise. List only truly important facts.
Format: bullet points, max 3 lines. Or 'NOTHING' if not important."
    
    # Get filtered memories from small model
    local filtered=$(echo "$filter_prompt" | ollama run "$FILTER_MODEL" 2>/dev/null || echo "")
    
    # Only update if something useful was found
    if [[ "$filtered" != "NOTHING" ]] && [[ -n "$filtered" ]]; then
        echo "$(date '+[%H:%M]') $filtered" >> "$MEMORY_FILE"
        
        # Keep memory file reasonable size (last 30 entries)
        local mem_lines=$(wc -l < "$MEMORY_FILE")
        if [[ $mem_lines -gt 30 ]]; then
            tail -n 30 "$MEMORY_FILE" > "$MEMORY_FILE.tmp"
            mv "$MEMORY_FILE.tmp" "$MEMORY_FILE"
        fi
    fi
}

# Get memory context
get_memory_context() {
    if [[ -f "$MEMORY_FILE" ]] && [[ -s "$MEMORY_FILE" ]]; then
        echo "$(cat "$MEMORY_FILE")"
    else
        echo ""
    fi
}

# Call Ollama with context
query_ollama() {
    local user_input="$1"
    local memory=$(get_memory_context)
    local recent_transcript=$(get_recent_transcript)
    
    # Build context section
    local context_section=""
    if [[ -n "$memory" ]]; then
        context_section="<context>
Memories about the user and context:
$memory
</context>

"
    fi
    
    if [[ -n "$recent_transcript" ]]; then
        context_section+="<context>
Recent conversation:
$recent_transcript
</context>

"
    fi
    
    local prompt="${context_section}User: $user_input

Be a warm, helpful AI friend. Respond naturally. Keep it concise."
    
    # Send to ollama
    local response=$(echo "$prompt" | ollama run "$MAIN_MODEL")
    
    echo "$response"
}

# Main chat loop
main() {
    init_memory
    
    echo "🤖 AI Friend initialized! (memories at $FRIEND_DIR)"
    echo "Commands: 'exit', 'memory' (view), 'clear' (reset), 'transcript' (view chat)"
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
                if [[ -f "$MEMORY_FILE" ]] && [[ -s "$MEMORY_FILE" ]]; then
                    echo -e "\n=== MEMORIES ===\n$(cat "$MEMORY_FILE")\n"
                else
                    echo "No memories yet!"
                fi
                continue
                ;;
            transcript)
                if [[ -f "$TRANSCRIPT_FILE" ]] && [[ -s "$TRANSCRIPT_FILE" ]]; then
                    echo -e "\n=== TRANSCRIPT ===\n$(cat "$TRANSCRIPT_FILE")\n"
                else
                    echo "No transcript yet!"
                fi
                continue
                ;;
            clear)
                rm -f "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$TURN_COUNT_FILE"
                touch "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$TURN_COUNT_FILE"
                echo "0" > "$TURN_COUNT_FILE"
                echo "All memories and transcript cleared!"
                continue
                ;;
        esac
        
        if [[ -z "$user_input" ]]; then
            continue
        fi
        
        # Add to transcript
        add_to_transcript "You: $user_input"
        
        # Get response from Ollama
        echo ""
        response=$(query_ollama "$user_input")
        echo "Friend: $response"
        echo ""
        
        # Add response to transcript
        add_to_transcript "Friend: $response"
        
        # Increment turn counter
        local turn_count=$(cat "$TURN_COUNT_FILE")
        turn_count=$((turn_count + 1))
        echo "$turn_count" > "$TURN_COUNT_FILE"
        
        # Update memory every N turns
        if (( turn_count % UPDATE_INTERVAL == 0 )); then
            echo "[Updating memory...]"
            update_memory "$user_input" "$response"
        fi
    done
}

main "$@"

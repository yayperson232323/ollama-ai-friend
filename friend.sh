#!/bin/bash

# AI Friend Chatbot with Ollama
# Stores memories and transcript in ~/.friend/
# Uses mistral for both conversation and memory
# Usage: ./friend.sh

FRIEND_DIR="$HOME/.friend"
MEMORY_FILE="$FRIEND_DIR/memory.txt"
TRANSCRIPT_FILE="$FRIEND_DIR/transcript.txt"
TURN_COUNT_FILE="$FRIEND_DIR/turn_count.txt"
PENDING_FILE="$FRIEND_DIR/pending.txt"

MAIN_MODEL="mistral"  # Main conversation model
FILTER_MODEL="mistral"  # Model for memory filtering
TRANSCRIPT_LINES=10  # Keep last 5 messages (2 lines per message)
EXTRACT_INTERVAL=5  # Extract and consolidate memory every 5 turns

# Initialize memory directory and files
init_memory() {
    if [[ ! -d "$FRIEND_DIR" ]]; then
        mkdir -p "$FRIEND_DIR"
    fi
    
    for file in "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$PENDING_FILE"; do
        if [[ ! -f "$file" ]]; then
            touch "$file"
        fi
    done
    
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
    
    local total_lines=$(wc -l < "$TRANSCRIPT_FILE")
    if [[ $total_lines -gt $TRANSCRIPT_LINES ]]; then
        tail -n "$TRANSCRIPT_LINES" "$TRANSCRIPT_FILE" > "$TRANSCRIPT_FILE.tmp"
        mv "$TRANSCRIPT_FILE.tmp" "$TRANSCRIPT_FILE"
    fi
}

# Extract what matters: facts, emotions, connections, mood
extract_facts_immediate() {
    local user_input="$1"
    local bot_response="$2"
    
    local extract_prompt="Extract what matters about this exchange - emotions, states, connections, preferences, names, facts. Be human.
User: $user_input
AI: $bot_response
List one thing you notice (or skip if genuinely nothing). Max 1 line."
    
    local facts=$(echo "$extract_prompt" | timeout 10s ollama run "$FILTER_MODEL" 2>/dev/null || echo "")
    
    # Only skip if truly empty or just whitespace
    if [[ -n "$facts" ]] && [[ "$facts" != "skip" ]]; then
        echo "[$(date '+%H:%M')] $facts" >> "$PENDING_FILE"
    fi
}

# Consolidate pending memories (runs every 5 turns)
consolidate_memories() {
    if [[ ! -f "$PENDING_FILE" ]] || [[ ! -s "$PENDING_FILE" ]]; then
        return
    fi
    
    local pending=$(cat "$PENDING_FILE")
    local current_memory=$(cat "$MEMORY_FILE" 2>/dev/null || echo "")
    
    local consolidate_prompt="Merge these into a living memory - keep what's real and matters:
Current:
$current_memory

New:
$pending

Output max 15 lines. Keep emotions, patterns, names, what you're learning about them."
    
    local consolidated=$(echo "$consolidate_prompt" | timeout 10s ollama run "$FILTER_MODEL" 2>/dev/null || echo "")
    
    if [[ -n "$consolidated" ]]; then
        echo "$consolidated" > "$MEMORY_FILE"
    fi
    
    > "$PENDING_FILE"
}

# Get memory context
get_memory_context() {
    if [[ -f "$MEMORY_FILE" ]] && [[ -s "$MEMORY_FILE" ]]; then
        cat "$MEMORY_FILE"
    fi
}

# Call Ollama with context - emotional, listening, heartfelt
query_ollama() {
    local user_input="$1"
    local memory=$(get_memory_context)
    local recent_transcript=$(get_recent_transcript)
    
    local context_section=""
    if [[ -n "$memory" ]]; then
        context_section="<context>
What I know about you:
$memory
</context>

"
    fi
    
    if [[ -n "$recent_transcript" ]]; then
        context_section+="<context>
Our conversation:
$recent_transcript
</context>

"
    fi
    
    local prompt="${context_section}User: $user_input

Be real. Be an actual friend - listen, feel what they're saying, respond with heart. Don't be corporate or over-nice. Be honest. Care. Be you."
    
    echo "$prompt" | ollama run "$MAIN_MODEL" 2>/dev/null || echo "I'm here, just thinking..."
}

# Main chat loop
main() {
    init_memory
    
    echo "🤖 AI Friend here. (memories at $FRIEND_DIR)"
    echo "Commands: 'exit', 'memory', 'transcript', 'clear'"
    echo ""
    
    while true; do
        read -p "You: " user_input
        
        case "$user_input" in
            exit|quit)
                echo "Take care of yourself, yeah?"
                break
                ;;
            memory)
                if [[ -f "$MEMORY_FILE" ]] && [[ -s "$MEMORY_FILE" ]]; then
                    echo -e "\n=== What I know about you ===\n$(cat "$MEMORY_FILE")\n"
                else
                    echo "Still getting to know you..."
                fi
                continue
                ;;
            transcript)
                if [[ -f "$TRANSCRIPT_FILE" ]] && [[ -s "$TRANSCRIPT_FILE" ]]; then
                    echo -e "\n=== Our conversation ===\n$(cat "$TRANSCRIPT_FILE")\n"
                else
                    echo "Fresh start."
                fi
                continue
                ;;
            clear)
                rm -f "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$TURN_COUNT_FILE" "$PENDING_FILE"
                init_memory
                echo "Cleared. Starting fresh."
                continue
                ;;
        esac
        
        if [[ -z "$user_input" ]]; then
            continue
        fi
        
        add_to_transcript "You: $user_input"
        
        echo ""
        response=$(query_ollama "$user_input")
        echo "Friend: $response"
        echo ""
        
        add_to_transcript "Friend: $response"
        
        local turn_count=$(cat "$TURN_COUNT_FILE")
        turn_count=$((turn_count + 1))
        echo "$turn_count" > "$TURN_COUNT_FILE"
        
        # Extract what matters in background
        extract_facts_immediate "$user_input" "$response" &
        
        # Consolidate every 5 turns
        if (( turn_count % EXTRACT_INTERVAL == 0 )); then
            echo "[learning...]"
            consolidate_memories
        fi
    done
}

main "$@"

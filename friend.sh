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
PENDING_FILE="$FRIEND_DIR/pending.txt"

MAIN_MODEL="qwen3.5:2b"  # Main conversation model
FILTER_MODEL="gemma3:1b"  # Small model for memory filtering
TRANSCRIPT_LINES=10  # Keep last 5 messages (2 lines per message)
EXTRACT_INTERVAL=5  # Extract and consolidate memory every 5 turns
MEMORY_MAX_LINES=40  # Keep memory file compact

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
    
    if [[ ! -f "$PENDING_FILE" ]]; then
        touch "$PENDING_FILE"
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

# Extract facts immediately without waiting (fast pass)
extract_facts_immediate() {
    local user_input="$1"
    local bot_response="$2"
    
    # Quick extraction prompt - looks for names, dates, facts
    local extract_prompt="Extract ONLY factual information (names, dates, preferences, facts). Be very brief.

User: $user_input
AI: $bot_response

List facts only (one per line, max 2-3 lines). Or 'NONE' if no facts."
    
    local facts=$(timeout 15s bash -c "echo \"\$1\" | ollama run \"$FILTER_MODEL\"" -- "$extract_prompt" 2>/dev/null || echo "")
    
    if [[ "$facts" != "NONE" ]] && [[ -n "$facts" ]]; then
        # Append to pending file with timestamp
        echo "$(date '+[%H:%M]') $facts" >> "$PENDING_FILE"
    fi
}

# Parse and consolidate pending memories into main memory (slower, periodic)
consolidate_memories() {
    if [[ ! -f "$PENDING_FILE" ]] || [[ ! -s "$PENDING_FILE" ]]; then
        return
    fi
    
    # Get pending facts
    local pending=$(cat "$PENDING_FILE")
    
    # Get current memory
    local current_memory=$(cat "$MEMORY_FILE" 2>/dev/null || echo "")
    
    # Build consolidation prompt - remove duplicates, merge info
    local consolidate_prompt="You are a memory consolidator. Merge new facts with existing memories, removing duplicates and keeping only essential info.

Existing memories:
$current_memory

New facts:
$pending

Task: Merge these into a concise memory list. Remove duplicates. Keep names, dates, preferences, important facts.
Format: one concise line per fact. Max 20 lines total."
    
    local consolidated=$(timeout 20s bash -c "echo \"\$1\" | ollama run \"$FILTER_MODEL\"" -- "$consolidate_prompt" 2>/dev/null || echo "")
    
    if [[ -n "$consolidated" ]] && [[ "$consolidated" != "NONE" ]]; then
        # Replace memory file with consolidated version
        echo "$consolidated" > "$MEMORY_FILE"
    fi
    
    # Clear pending file
    > "$PENDING_FILE"
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
    local response=$(echo "$prompt" | ollama run "$MAIN_MODEL" 2>/dev/null || echo "Sorry, I'm having trouble thinking right now.")
    
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
                rm -f "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$TURN_COUNT_FILE" "$PENDING_FILE"
                touch "$MEMORY_FILE" "$TRANSCRIPT_FILE" "$TURN_COUNT_FILE" "$PENDING_FILE"
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
        
        # Extract facts immediately (fast)
        extract_facts_immediate "$user_input" "$response"
        
        # Consolidate memories every N turns (slower)
        if (( turn_count % EXTRACT_INTERVAL == 0 )); then
            echo "[Consolidating memories...]"
            consolidate_memories
        fi
    done
}

main "$@"

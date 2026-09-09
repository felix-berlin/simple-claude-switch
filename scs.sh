#!/bin/bash
# scs.sh — switch between multiple Claude Code accounts without keeping
# separate CLAUDE_CONFIG_DIRs around.
#
# Idea: there is only ONE config directory (~/.claude or $CLAUDE_CONFIG_DIR).
# Switching only swaps the account-specific fields:
#   - claudeAiOauth  in  $CLAUDE_CONFIG_DIR/.credentials.json   (token)
#   - oauthAccount   in  ~/.claude.json                         (account identity)
# Everything else (MCP servers, project history, settings, plugins) stays
# untouched and is never duplicated.
#
# Requires: jq (sudo apt install jq)
#
# Install:
#   1. Put this file at e.g. ~/.scs.sh
#   2. Add to ~/.bashrc or ~/.zshrc:  source ~/.scs.sh
#   3. Restart your terminal or: source ~/.bashrc
#
# Workflow:
#   claude                # log in (account A)
#   scs save work         # save the current login as profile "work"
#   claude /logout && claude   # log in (account B)
#   scs save personal
#   scs use work          # switch back any time, no login needed
#   scs use personal

SCS_PROFILES_DIR="$HOME/.scs-profiles"
SCS_ACTIVE_FILE="$HOME/.scs-active-account"
SCS_JSON="$HOME/.claude.json"

_scs_creds_file() {
    echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
}

scs() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required: sudo apt install jq"
        return 1
    fi

    local cmd="$1"
    shift
    local creds_file
    creds_file="$(_scs_creds_file)"

    case "$cmd" in
        save)
            local name="$1"
            if [ -z "$name" ]; then
                echo "Usage: scs save <name>"
                return 1
            fi
            if [ ! -f "$creds_file" ] || [ ! -f "$SCS_JSON" ]; then
                echo "No active login found. Run 'claude' and log in first."
                return 1
            fi
            mkdir -p "$SCS_PROFILES_DIR/$name"
            jq '{claudeAiOauth: .claudeAiOauth}' "$creds_file" > "$SCS_PROFILES_DIR/$name/credentials.json"
            jq '{oauthAccount: .oauthAccount}' "$SCS_JSON" > "$SCS_PROFILES_DIR/$name/account.json"
            echo "$name" > "$SCS_ACTIVE_FILE"
            echo "Current login saved as profile '$name'."
            ;;
        use)
            local name="$1"
            if [ -z "$name" ]; then
                echo "Usage: scs use <name>"
                return 1
            fi
            local profile_dir="$SCS_PROFILES_DIR/$name"
            if [ ! -d "$profile_dir" ]; then
                echo "Profile '$name' does not exist. Save it first with: scs save $name"
                return 1
            fi

            # backup of the currently active login
            [ -f "$creds_file" ] && cp "$creds_file" "$creds_file.bak"
            [ -f "$SCS_JSON" ] && cp "$SCS_JSON" "$SCS_JSON.bak"

            jq -s '.[0] * .[1]' "$creds_file" "$profile_dir/credentials.json" > "$creds_file.tmp" \
                && mv "$creds_file.tmp" "$creds_file"
            jq -s '.[0] * .[1]' "$SCS_JSON" "$profile_dir/account.json" > "$SCS_JSON.tmp" \
                && mv "$SCS_JSON.tmp" "$SCS_JSON"

            echo "$name" > "$SCS_ACTIVE_FILE"
            echo "Active Claude account: $name"

            if ! command -v pgrep >/dev/null 2>&1; then
                echo "pgrep not available (e.g. Git Bash without procps) — restart Claude CLI sessions manually."
            else
                local reply
                read -r -p "Kill running Claude CLI sessions now so they restart as '$name'? [y/N] " reply
                if [[ "$reply" =~ ^[Yy]$ ]]; then
                    # ponytail: only matches the CLI binary path and excludes
                    # claude-mem's internal sub-agent calls (marked by
                    # --disallowedTools). Doesn't touch the VS Code extension,
                    # see note below — no ancestry-based kill detection yet,
                    # add if needed.
                    local pid pids=""
                    for pid in $(pgrep -f "$HOME/.local/bin/claude "); do
                        ps -p "$pid" -o args= 2>/dev/null | grep -q -- "--disallowedTools" && continue
                        pids="$pids $pid"
                    done
                    if [ -n "$pids" ]; then
                        kill $pids 2>/dev/null
                        echo "Killed:$pids"
                    else
                        echo "No running Claude CLI session found."
                    fi
                fi
            fi
            echo "VS Code: the Claude extension does not reconnect automatically — use Command Palette -> 'Developer: Reload Window'."
            ;;
        list)
            echo "Saved profiles:"
            local active
            active="$(cat "$SCS_ACTIVE_FILE" 2>/dev/null)"
            for dir in "$SCS_PROFILES_DIR"/*/; do
                [ -d "$dir" ] || continue
                local name
                name="$(basename "$dir")"
                if [ "$name" = "$active" ]; then
                    echo "  * $name (active)"
                else
                    echo "    $name"
                fi
            done
            ;;
        current)
            if [ -f "$SCS_JSON" ]; then
                jq -r '.oauthAccount // "unknown"' "$SCS_JSON" 2>/dev/null
            fi
            echo "assigned profile: $(cat "$SCS_ACTIVE_FILE" 2>/dev/null || echo "none")"
            ;;
        remove)
            local name="$1"
            if [ -z "$name" ]; then
                echo "Usage: scs remove <name>"
                return 1
            fi
            rm -rf "$SCS_PROFILES_DIR/$name"
            echo "Profile '$name' removed."
            ;;
        *)
            echo "Usage: scs {save|use|list|current|remove} [name]"
            ;;
    esac
}

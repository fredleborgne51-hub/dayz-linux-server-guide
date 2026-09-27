#!/bin/bash
# -------------------------------------------------------------------
# Project : DayZ Dedicated Linux Server
#
# Script : update.sh
# Version : 0.3.0
#
# Administration author :
#   FredLeBorgne
#
# Design and analysis assistance :
#   ChatGPT (OpenAI)
#
# Description :
# Shared Workshop management
#
# Updates :
#   - DayZ server
#   - Workshop mods
#   - mod symbolic links
#   - .bikey key files
#
# Exit codes :
#   0  = update completed successfully
#   78 = state does not allow the server to start
#
# Code 78 corresponds to EX_CONFIG (sysexits).
# -------------------------------------------------------------------
set -euo pipefail

SCRIPT_VERSION="0.3.0"

SERVER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVER_NAME="$(basename "$SERVER")"

MODS_FILE="$SERVER/mods.conf"
MOD_LIST=""
MOD_LIST_FILE="$SERVER/mod_list.conf"

STEAMCMD="$(dirname "$SERVER")/steamcmd/steamcmd.sh"
WORKSHOP_DIR="$(dirname "$SERVER")/workshop_shared"

STEAM_USER="YOUR_STEAM_ACCOUNT"
WORKSHOP_APP_ID="221100"
DAYZ_APP_ID="223350"

log() {
    echo "[$SERVER_NAME] $*"
}

error() {
    echo "[$SERVER_NAME] ERROR: $*" >&2
}

fatal() {
    error "$*"
    exit 78
}

if [[ ! -d "$SERVER" ]]; then
    fatal "server directory not found: $SERVER"
fi

if [[ ! -f "$MODS_FILE" ]]; then
    fatal "mods.conf not found: $MODS_FILE"
fi

if [[ ! -x "$STEAMCMD" ]]; then
    fatal "SteamCMD not found or not executable: $STEAMCMD"
fi

if [[ ! -d "$WORKSHOP_DIR" ]]; then
    fatal "shared Workshop directory not found: $WORKSHOP_DIR"
fi

mkdir -p "$SERVER/keys"

MOD_IDS=()
MOD_NAMES=()
while IFS='|' read -r MOD_ID MOD_NAME; do
    MOD_ID="${MOD_ID#"${MOD_ID%%[![:space:]]*}"}"
    MOD_ID="${MOD_ID%"${MOD_ID##*[![:space:]]}"}"
    MOD_NAME="${MOD_NAME#"${MOD_NAME%%[![:space:]]*}"}"
    MOD_NAME="${MOD_NAME%"${MOD_NAME##*[![:space:]]}"}"

    [[ -z "$MOD_ID" ]] && continue
    [[ "$MOD_ID" =~ ^# ]] && continue

    if ! [[ "$MOD_ID" =~ ^[0-9]+$ ]]; then
        fatal "invalid Workshop ID: $MOD_ID"
    fi
    if [[ -z "$MOD_NAME" ]]; then
        fatal "missing mod name for Workshop ID: $MOD_ID"
    fi

    if [[ "$MOD_NAME" != @* ]]; then
        fatal "invalid mod name: $MOD_NAME; name must start with @"
    fi

    MOD_IDS+=("$MOD_ID")
    MOD_NAMES+=("$MOD_NAME")
done < "$MODS_FILE"

log "Script version: $SCRIPT_VERSION"
log "Configured mods: ${#MOD_IDS[@]}"

log "Updating / verifying DayZ server..."
if ! "$STEAMCMD" \
    +force_install_dir "$SERVER/" \
    +login "$STEAM_USER" \
    +app_update "$DAYZ_APP_ID" \
    +quit
then
    fatal "DayZ server update failed."
fi

log "DayZ server: update completed."

if [[ "${#MOD_IDS[@]}" -gt 0 ]]; then
    log "Updating ${#MOD_IDS[@]} Workshop mods..."

    STEAM_MOD_ARGS=(
        +force_install_dir "$WORKSHOP_DIR/"
        +login "$STEAM_USER"
    )
    for MOD_ID in "${MOD_IDS[@]}"; do
        log "Workshop: preparing mod $MOD_ID"
        STEAM_MOD_ARGS+=(
            +workshop_download_item "$WORKSHOP_APP_ID" "$MOD_ID"
        )
    done

    STEAM_MOD_ARGS+=(+quit)

    if ! "$STEAMCMD" "${STEAM_MOD_ARGS[@]}"; then
        fatal "Workshop mods update failed."
    fi

    log "Mods update completed."
else
    log "No active mods in mods.conf."
fi

log "Preparing mod symbolic links..."
for INDEX in "${!MOD_IDS[@]}"; do
    MOD_ID="${MOD_IDS[$INDEX]}"
    MOD_NAME="${MOD_NAMES[$INDEX]}"

    MOD_PATH="$WORKSHOP_DIR/steamapps/workshop/content/$WORKSHOP_APP_ID/$MOD_ID"
    LINK_PATH="$SERVER/$MOD_NAME"

    if [[ ! -d "$MOD_PATH" ]]; then
        fatal "mod missing after download: $MOD_ID"
    fi

    if [[ -L "$LINK_PATH" ]]; then
        CURRENT_TARGET="$(readlink -f "$LINK_PATH")"
        EXPECTED_TARGET="$(readlink -f "$MOD_PATH")"
        if [[ "$CURRENT_TARGET" == "$EXPECTED_TARGET" ]]; then
            log "Link already correct: $MOD_ID"
            continue
        fi

        log "Incorrect link detected: $LINK_PATH"
        log "Previous target: $CURRENT_TARGET"
        log "New target: $EXPECTED_TARGET"

        rm "$LINK_PATH"
    fi

    if [[ -e "$LINK_PATH" ]]; then
        fatal "a file/directory already exists: $LINK_PATH"
    fi

    ln -s "$MOD_PATH" "$LINK_PATH"
    log "Link created: $MOD_ID"
done

log "Searching for .bikey keys..."

for MOD_ID in "${MOD_IDS[@]}"; do
    MOD_PATH="$WORKSHOP_DIR/steamapps/workshop/content/$WORKSHOP_APP_ID/$MOD_ID"

    KEY_DIR="$(
        find "$MOD_PATH" \
            -maxdepth 2 \
            -type d \
            \( -iname "key" -o -iname "keys" \) \
            -print \
            -quit
    )"

    if [[ -z "$KEY_DIR" ]]; then
        log "No key found: $MOD_ID"
        continue
    fi

    log "Keys found in: $MOD_ID/$(basename "$KEY_DIR")"
    while IFS= read -r -d '' KEY; do
        KEY_NAME="$(basename "$KEY")"

        EXISTING_KEY="$(
            find "$SERVER/keys" \
                -maxdepth 1 \
                -type f \
                -iname "$KEY_NAME" \
                -print \
                -quit
        )"

        if [[ -z "$EXISTING_KEY" ]]; then
            cp "$KEY" "$SERVER/keys/$KEY_NAME"
            log "Key copied: $KEY_NAME"
            continue
        fi
        if cmp -s "$KEY" "$EXISTING_KEY"; then
            log "Key already present: $(basename "$EXISTING_KEY")"
            continue
        fi

        fatal "key conflict: $KEY_NAME; source: $KEY; existing: $EXISTING_KEY; both files have the same name but different contents."
    done < <(
        find "$KEY_DIR" \
            -maxdepth 1 \
            -type f \
            -iname "*.bikey" \
            -print0
    )
done

MOD_LIST="$(IFS=';'; echo "${MOD_NAMES[*]}")"
printf '%s\n' "$MOD_LIST" > "$MOD_LIST_FILE"

log "Mod list saved to: $MOD_LIST_FILE"
log "Active mods: $MOD_LIST"
log "Update completed successfully."

exit 0

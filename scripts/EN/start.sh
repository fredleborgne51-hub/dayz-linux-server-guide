#!/bin/bash
# -------------------------------------------------------------------
# Project : DayZ Dedicated Linux Server
#
# Script :
#   start.sh
#
# Version :
#   0.2.0
#
# Administration author :
#   FredLeBorgne
#
# Design and analysis assistance :
#   ChatGPT (OpenAI)
#
# Description :
#   Starts the DayZ Dedicated Linux server.
#
#   The mod list is generated exclusively by update.sh
#   and stored in :
#
#       $SERVER/mod_list.conf
#
# Behavior :
#
#   - mod_list.conf missing :
#       ERROR - startup refused
#
#   - mod_list.conf present but empty :
#       intentional VANILLA startup
#
#   - mod_list.conf present and not empty :
#       startup with the listed mods
# -------------------------------------------------------------------
set -uo pipefail

SCRIPT_VERSION="0.2.0"

SERVER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MOD_LIST_FILE="$SERVER/mod_list.conf"

echo "Script version: $SCRIPT_VERSION"
echo "Server: $SERVER"

if [[ ! -d "$SERVER" ]]; then
    echo "ERROR: server directory not found: $SERVER" >&2
    exit 1
fi
if [[ ! -f "$MOD_LIST_FILE" ]]; then
    echo "ERROR: mod_list.conf not found." >&2
    echo "ERROR: the server will not be started." >&2
    echo "ERROR: run update.sh before start.sh." >&2
    exit 1
fi

MOD_LIST=$(cat "$MOD_LIST_FILE")
if [[ -z "${MOD_LIST// /}" ]]; then
    echo "INFO: mod_list.conf is present but empty."
    echo "INFO: starting in VANILLA mode."
else
    echo "INFO: mod list loaded from:"
    echo "       $MOD_LIST_FILE"
    echo
    echo "Loaded mods:"
    echo "$MOD_LIST"
    echo
fi

cd "$SERVER" || exit 1

if [[ -n "$MOD_LIST" ]]; then
    echo "INFO: starting DayZ with mods."
    exec ./DayZServer \
        -config=serverDZ.cfg \
        -port=2301 \
        "-mod=$MOD_LIST" \
        -BEpath=battleye \
        -profiles=profiles \
        -dologs \
        -adminlog \
        -netlog \
        -freezecheck
else
    echo "INFO: starting DayZ in VANILLA mode."

    exec ./DayZServer \
        -config=serverDZ.cfg \
        -port=2301 \
        -BEpath=battleye \
        -profiles=profiles \
        -dologs \
        -adminlog \
        -netlog \
        -freezecheck
fi

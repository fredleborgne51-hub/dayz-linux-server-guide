#!/bin/bash

# -------------------------------------------------------------------
# Projet : Serveur DayZ Dedicated Linux
#
# Script : update.sh
# Version : 0.3.0
#
# Auteur administration :
#   FredLeBorgne
#
# Assistance conception et analyse :
#   ChatGPT (OpenAI)
#
# Description :
# Mutualisation du workshop
#
# Mise à jour :
#   - serveur DayZ
#   - mods Workshop
#   - liens symboliques des mods
#   - copie des clés .bikey
#
# Codes de sortie :
#   0  = mise à jour terminée avec succès
#   78 = état ne permettant pas de démarrer le serveur
#
# Le code 78 correspond à EX_CONFIG (sysexits).
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

STEAM_USER="VOTRE_COMPTE_STEAM"
WORKSHOP_APP_ID="221100"
DAYZ_APP_ID="223350"

log() {
    echo "[$SERVER_NAME] $*"
}

error() {
    echo "[$SERVER_NAME] ERREUR : $*" >&2
}

fatal() {
    error "$*"
    exit 78
}

if [[ ! -d "$SERVER" ]]; then
    fatal "répertoire serveur absent : $SERVER"
fi

if [[ ! -f "$MODS_FILE" ]]; then
    fatal "mods.conf absent : $MODS_FILE"
fi

if [[ ! -x "$STEAMCMD" ]]; then
    fatal "SteamCMD absent ou non exécutable : $STEAMCMD"
fi

if [[ ! -d "$WORKSHOP_DIR" ]]; then
    fatal "répertoire Workshop mutualisé absent : $WORKSHOP_DIR"
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
        fatal "Workshop ID invalide : $MOD_ID"
    fi

    if [[ -z "$MOD_NAME" ]]; then
        fatal "Nom de mod absent pour le Workshop ID : $MOD_ID"
    fi

    if [[ "$MOD_NAME" != @* ]]; then
        fatal "Nom de mod invalide : $MOD_NAME ; le nom doit commencer par @"
    fi

    MOD_IDS+=("$MOD_ID")
    MOD_NAMES+=("$MOD_NAME")
done < "$MODS_FILE"

log "Version du script : $SCRIPT_VERSION"
log "Mods configurés : ${#MOD_IDS[@]}"

log "Mise à jour / validation du serveur DayZ..."

if ! "$STEAMCMD" \
    +force_install_dir "$SERVER/" \
    +login "$STEAM_USER" \
    +app_update "$DAYZ_APP_ID" \
    +quit
then
    fatal "échec de la mise à jour du serveur DayZ."
fi

log "Serveur DayZ : mise à jour terminée."

if [[ "${#MOD_IDS[@]}" -gt 0 ]]; then
    log "Mise à jour des ${#MOD_IDS[@]} mods Workshop..."

    STEAM_MOD_ARGS=(
        +force_install_dir "$WORKSHOP_DIR/"
        +login "$STEAM_USER"
    )

    for MOD_ID in "${MOD_IDS[@]}"; do
        log "Workshop : préparation du mod $MOD_ID"
        STEAM_MOD_ARGS+=(
            +workshop_download_item "$WORKSHOP_APP_ID" "$MOD_ID"
        )
    done

    STEAM_MOD_ARGS+=(+quit)

    if ! "$STEAMCMD" "${STEAM_MOD_ARGS[@]}"; then
        fatal "échec de la mise à jour des mods Workshop."
    fi

    log "Mise à jour des mods terminée."
else
    log "Aucun mod actif dans mods.conf."
fi

log "Préparation des liens symboliques des mods..."

for INDEX in "${!MOD_IDS[@]}"; do
    MOD_ID="${MOD_IDS[$INDEX]}"
    MOD_NAME="${MOD_NAMES[$INDEX]}"

    MOD_PATH="$WORKSHOP_DIR/steamapps/workshop/content/$WORKSHOP_APP_ID/$MOD_ID"
    LINK_PATH="$SERVER/$MOD_NAME"

    if [[ ! -d "$MOD_PATH" ]]; then
        fatal "mod absent après téléchargement : $MOD_ID"
    fi

    if [[ -L "$LINK_PATH" ]]; then
        CURRENT_TARGET="$(readlink -f "$LINK_PATH")"
        EXPECTED_TARGET="$(readlink -f "$MOD_PATH")"

        if [[ "$CURRENT_TARGET" == "$EXPECTED_TARGET" ]]; then
            log "Lien déjà correct : $MOD_ID"
            continue
        fi

        log "Lien incorrect détecté : $LINK_PATH"
        log "Ancienne cible : $CURRENT_TARGET"
        log "Nouvelle cible : $EXPECTED_TARGET"

        rm "$LINK_PATH"
    fi

    if [[ -e "$LINK_PATH" ]]; then
        fatal "un fichier/répertoire existe déjà : $LINK_PATH"
    fi

    ln -s "$MOD_PATH" "$LINK_PATH"
    log "Lien créé : $MOD_ID"
done

log "Recherche des clés .bikey..."

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
        log "Aucune clé : $MOD_ID"
        continue
    fi

    log "Clés trouvées dans : $MOD_ID/$(basename "$KEY_DIR")"

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
            log "Clé copiée : $KEY_NAME"
            continue
        fi

        if cmp -s "$KEY" "$EXISTING_KEY"; then
            log "Clé déjà présente : $(basename "$EXISTING_KEY")"
            continue
        fi

        fatal "conflit de clé : $KEY_NAME ; source : $KEY ; existante : $EXISTING_KEY ; les deux fichiers portent le même nom mais leur contenu diffère."
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

log "Liste des mods sauvegardée dans : $MOD_LIST_FILE"
log "Mods actifs : $MOD_LIST"
log "Mise à jour terminée avec succès."

exit 0

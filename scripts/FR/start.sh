#!/bin/bash

# -------------------------------------------------------------------
# Projet : Serveur DayZ Dedicated Linux
#
# Script :
#   start.sh
#
# Version :
#   0.2.0
#
# Auteur administration :
#   FredLeBorgne
#
# Assistance conception et analyse :
#   ChatGPT (OpenAI)
#
# Description :
#   Démarrage du serveur DayZ Dedicated Linux.
#
#   La liste des mods est générée exclusivement par update.sh
#   et stockée dans :
#
#       $SERVER/mod_list.conf
#
# Comportement :
#
#   - mod_list.conf absent :
#       ERREUR - démarrage refusé
#
#   - mod_list.conf présent mais vide :
#       démarrage VANILLA volontaire
#
#   - mod_list.conf présent et non vide :
#       démarrage avec les mods indiqués
# -------------------------------------------------------------------

set -uo pipefail

SCRIPT_VERSION="0.2.0"

SERVER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MOD_LIST_FILE="$SERVER/mod_list.conf"

echo "Version du script : $SCRIPT_VERSION"
echo "Serveur : $SERVER"

if [[ ! -d "$SERVER" ]]; then
    echo "ERREUR : répertoire serveur absent : $SERVER" >&2
    exit 1
fi

if [[ ! -f "$MOD_LIST_FILE" ]]; then
    echo "ERREUR : mod_list.conf absent." >&2
    echo "ERREUR : le serveur ne sera pas démarré." >&2
    echo "ERREUR : exécuter update.sh avant start.sh." >&2
    exit 1
fi

MOD_LIST=$(cat "$MOD_LIST_FILE")

if [[ -z "${MOD_LIST// /}" ]]; then
    echo "INFO : mod_list.conf est présent mais vide."
    echo "INFO : démarrage en mode VANILLA."
else
    echo "INFO : liste des mods chargée depuis :"
    echo "       $MOD_LIST_FILE"
    echo
    echo "Mods chargés :"
    echo "$MOD_LIST"
    echo
fi

cd "$SERVER" || exit 1

if [[ -n "$MOD_LIST" ]]; then
    echo "INFO : lancement de DayZ avec les mods."

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
    echo "INFO : lancement de DayZ en mode VANILLA."

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

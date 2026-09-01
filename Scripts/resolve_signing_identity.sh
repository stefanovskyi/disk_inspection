#!/bin/zsh

set -euo pipefail

local_identity="SpaceLens Local Development"
requested_identity="${SPACELENS_CODESIGN_IDENTITY:-}"

if (( ${+SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES} )); then
    available_identities="$SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES"
else
    available_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
fi

identity_is_available() {
    local candidate="$1"

    if [[ "$candidate" =~ '^[[:xdigit:]]{40}$' ]]; then
        [[ "$available_identities" == *"$candidate"* ]]
    else
        [[ "$available_identities" == *\"${candidate}\"* ]]
    fi
}

if [[ "$requested_identity" == "-" ]]; then
    print -r -- "-"
    exit 0
fi

if [[ -n "$requested_identity" ]]; then
    if ! identity_is_available "$requested_identity"; then
        echo "Configured code-signing identity was not found: $requested_identity" >&2
        echo "Run 'security find-identity -v -p codesigning' to list available identities." >&2
        exit 2
    fi

    print -r -- "$requested_identity"
    exit 0
fi

if identity_is_available "$local_identity"; then
    print -r -- "$local_identity"
else
    print -r -- "-"
fi

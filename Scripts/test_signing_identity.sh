#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
resolver="$project_dir/Scripts/resolve_signing_identity.sh"

fail() {
    echo "Signing identity test failed: $1" >&2
    exit 1
}

resolved="$(
    SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES="" \
    "$resolver"
)" || fail "resolver did not support an empty keychain"
[[ "$resolved" == "-" ]] || fail "empty keychain did not select ad-hoc signing"

local_identity='SpaceLens Local Development'
resolved="$(
    SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES="  1) ABCDEF \"$local_identity\"" \
    "$resolver"
)" || fail "resolver did not detect the local SpaceLens identity"
[[ "$resolved" == "$local_identity" ]] || fail "local SpaceLens identity was not selected"

apple_identity='Apple Development: Example Developer (ABCDE12345)'
resolved="$(
    SPACELENS_CODESIGN_IDENTITY="$apple_identity" \
    SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES="  1) 123456 \"$apple_identity\"" \
    "$resolver"
)" || fail "resolver rejected an available configured identity"
[[ "$resolved" == "$apple_identity" ]] || fail "configured identity was not selected"

if SPACELENS_CODESIGN_IDENTITY="Missing Identity" \
    SPACELENS_AVAILABLE_CODE_SIGNING_IDENTITIES="" \
    "$resolver" >/dev/null 2>&1; then
    fail "resolver accepted a missing configured identity"
fi

echo "Signing identity tests passed"

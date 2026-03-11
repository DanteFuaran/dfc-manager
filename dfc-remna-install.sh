#!/bin/bash
# Backward compatibility shim — redirects to remnawave.sh
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec "${SCRIPT_DIR}/remnawave.sh" "$@"

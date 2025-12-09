#!/usr/bin/env bash
# Backwards-compatible wrapper for the consolidated deploy script
# Delegates to scripts/deploy.sh create-lxc

set -euo pipefail
IFS=$'\n\t'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$DIR/deploy.sh" ]]; then
	echo "Consolidated deploy script not found at $DIR/deploy.sh" >&2
	exit 2
fi

exec bash "$DIR/deploy.sh" create-lxc "$@"

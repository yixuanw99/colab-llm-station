#!/usr/bin/env bash
# Forwarding wrapper for backwards compatibility
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/scripts/sync_git.sh" "$@"

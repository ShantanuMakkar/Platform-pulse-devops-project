#!/usr/bin/env bash
# Refreshes SSO login, then writes short-lived static credentials straight
# into atlantis/.env — run this once at the start of each session, before
# `docker compose up`. Avoids the container ever needing to do an SSO
# browser refresh itself, which it can't do.
#
# Usage: ./refresh-creds.sh [profile-name]   (defaults to "dev")
set -euo pipefail

PROFILE="${1:-dev}"
ENV_FILE="$(dirname "$0")/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "atlantis/.env not found. Create it first (see README Phase 3)." >&2
  exit 1
fi

echo "Logging in to profile '$PROFILE'..."
aws sso login --profile "$PROFILE"

echo "Exporting temporary credentials into $ENV_FILE..."
CREDS="$(aws configure export-credentials --profile "$PROFILE" --format env-no-export)"

while IFS='=' read -r key value; do
  case "$key" in
    AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)
      if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
      else
        echo "${key}=${value}" >> "$ENV_FILE"
      fi
      ;;
  esac
done <<< "$CREDS"

echo "Done. Restart Atlantis to pick these up:"
echo "  docker compose --env-file .env down && docker compose --env-file .env up"

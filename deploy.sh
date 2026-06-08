#!/bin/bash
# Load token from .env and inject into hexo deploy config
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env file not found. Create it with GITHUB_DEPLOY_TOKEN=your_token"
  exit 1
fi

# Read token from .env
export $(grep -v '^#' "$ENV_FILE" | xargs)

if [ -z "$GITHUB_DEPLOY_TOKEN" ]; then
  echo "Error: GITHUB_DEPLOY_TOKEN not set in .env"
  exit 1
fi

# Temporarily add token to _config.yml for deploy, then remove it
CONFIG="$SCRIPT_DIR/_config.yml"
cp "$CONFIG" "$CONFIG.bak"
trap "mv '$CONFIG.bak' '$CONFIG'" EXIT

sed "s|repo: https://github.com/|repo: https://x-access-token:${GITHUB_DEPLOY_TOKEN}@github.com/|" "$CONFIG.bak" > "$CONFIG"

hexo deploy

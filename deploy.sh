#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env file found. Copy .env.example to .env and fill in your values."
  exit 1
fi

source .env

# Install flyctl if missing
if ! command -v fly &> /dev/null; then
  curl -L https://fly.io/install.sh | sh
  source ~/.zshrc
fi

# First-time setup
if [ ! -f fly.toml ]; then
  fly auth login
  fly launch
  fly certs add "$HOST"
fi

fly secrets set $(grep -v '^\s*#' .env | grep -v '^\s*$' | xargs)

fly deploy

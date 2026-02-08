#!/bin/bash
# Shared Linear API helpers for tmux-orchestrator scripts
# Repo-agnostic: discovers repo root via git, checks .env.local and .env for LINEAR_API_KEY

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"

if [ -z "$REPO_ROOT" ]; then
  echo "Error: Not inside a git repository"
  exit 1
fi

if [ -z "$LINEAR_API_KEY" ]; then
  for envfile in "$REPO_ROOT/.env.local" "$REPO_ROOT/.env"; do
    if [ -f "$envfile" ]; then
      _key=$(grep -E '^LINEAR_API_KEY=' "$envfile" | cut -d'=' -f2-)
      if [ -n "$_key" ]; then
        LINEAR_API_KEY="$_key"
        break
      fi
    fi
  done
  export LINEAR_API_KEY
fi

if [ -z "$LINEAR_API_KEY" ]; then
  echo "Error: LINEAR_API_KEY not found. Set it in .env.local or .env at repo root, or export it."
  exit 1
fi

REPO_NAME=$(basename "$REPO_ROOT")
WORKTREES_DIR="$(dirname "$REPO_ROOT")/${REPO_NAME}-worktrees"
ORCHESTRATOR_DIR="$REPO_ROOT/.orchestrator"

linear_gql() {
  local query="$1"
  local variables="$2"

  if [ -z "$variables" ]; then
    variables='{}'
  fi

  local clean_query
  clean_query=$(echo "$query" | tr '\n' ' ' | sed 's/  */ /g')

  local tmpfile
  tmpfile=$(mktemp)
  jq -n --arg q "$clean_query" --argjson v "$variables" \
    '{"query": $q, "variables": $v}' > "$tmpfile"

  local response
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    --data @"$tmpfile" \
    https://api.linear.app/graphql)

  rm -f "$tmpfile"

  if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
    echo "GraphQL Error: $(echo "$response" | jq -r '.errors[0].message')" >&2
    return 1
  fi

  echo "$response"
}

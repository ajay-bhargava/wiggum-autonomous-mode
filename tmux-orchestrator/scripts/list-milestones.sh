#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/linear-helpers.sh"

PROJECT_ID="$1"

if [ -z "$PROJECT_ID" ]; then
  echo "Usage: list-milestones.sh <PROJECT_ID>"
  echo ""
  echo "Run list-projects.sh first to get project IDs."
  exit 1
fi

QUERY='query($projectId: String!) {
  project(id: $projectId) {
    name
    projectMilestones(first: 20) {
      nodes {
        id
        name
        description
        targetDate
        sortOrder
        issues {
          nodes {
            id
            identifier
            title
            state { name }
          }
        }
      }
    }
  }
}'

VARIABLES=$(jq -n --arg id "$PROJECT_ID" '{projectId: $id}')
RESPONSE=$(linear_gql "$QUERY" "$VARIABLES")

PROJECT_NAME=$(echo "$RESPONSE" | jq -r '.data.project.name')

echo ""
echo "## Milestones for: $PROJECT_NAME"
echo ""
echo "| # | Milestone | Target Date | Issues | Open | Milestone ID |"
echo "|---|-----------|-------------|--------|------|--------------|"

echo "$RESPONSE" | jq -r '
  .data.project.projectMilestones.nodes | sort_by(.sortOrder) | to_entries[] |
  {
    idx: (.key + 1),
    name: .value.name,
    target: (.value.targetDate // "—"),
    total: (.value.issues.nodes | length),
    open: ([.value.issues.nodes[] | select(.state.name != "Done" and .state.name != "Canceled")] | length),
    id: .value.id
  } |
  "| \(.idx) | \(.name | gsub("\\|"; "–")) | \(.target) | \(.total) | \(.open) | `\(.id)` |"
'

echo ""
echo "Use a Milestone ID with start-milestone.sh to launch workers."

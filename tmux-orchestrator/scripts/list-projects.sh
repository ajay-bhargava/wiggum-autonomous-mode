#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/linear-helpers.sh"

QUERY='query {
  projects(first: 20, filter: { state: { in: ["started", "planned"] } }) {
    nodes {
      id
      name
      state
      progress
      projectMilestones {
        nodes {
          id
          name
        }
      }
    }
  }
}'

RESPONSE=$(linear_gql "$QUERY")

echo ""
echo "## Linear Projects (Active)"
echo ""
echo "| # | Project Name | Progress | Milestones | Project ID |"
echo "|---|-------------|----------|------------|------------|"

echo "$RESPONSE" | jq -r '
  .data.projects.nodes | to_entries[] |
  "| \(.key + 1) | \(.value.name | gsub("\\|"; "–")) | \(.value.progress // 0 | . * 100 | floor)% | \(.value.projectMilestones.nodes | length) | `\(.value.id)` |"
'

echo ""
echo "Use a Project ID with list-milestones.sh to see milestones."

#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/linear-helpers.sh"

MILESTONE_ID=""
MAX_WORKERS=6
AMP_MODE="smart"
DANGEROUSLY_ALLOW_ALL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-workers) MAX_WORKERS="$2"; shift 2 ;;
    --mode) AMP_MODE="$2"; shift 2 ;;
    --dangerously-allow-all) DANGEROUSLY_ALLOW_ALL="--dangerously-allow-all"; shift ;;
    *) MILESTONE_ID="$1"; shift ;;
  esac
done

if [ -z "$MILESTONE_ID" ]; then
  echo "Usage: start-milestone.sh <MILESTONE_ID> [--max-workers N] [--mode rush|smart|deep] [--dangerously-allow-all]"
  echo ""
  echo "Run list-milestones.sh first to get milestone IDs."
  exit 1
fi

# Fetch milestone + issues
QUERY='query($milestoneId: String!) {
  projectMilestone(id: $milestoneId) {
    id
    name
    description
    project { id name }
    issues(first: 50) {
      nodes {
        id
        identifier
        title
        description
        state { name }
        priority
        url
        branchName
        labels { nodes { name } }
      }
    }
  }
}'

VARIABLES=$(jq -n --arg id "$MILESTONE_ID" '{milestoneId: $id}')
RESPONSE=$(linear_gql "$QUERY" "$VARIABLES")

MILESTONE_NAME=$(echo "$RESPONSE" | jq -r '.data.projectMilestone.name')
PROJECT_NAME=$(echo "$RESPONSE" | jq -r '.data.projectMilestone.project.name')

if [ "$MILESTONE_NAME" = "null" ]; then
  echo "Error: Milestone not found: $MILESTONE_ID"
  exit 1
fi

echo ""
echo "## Starting Milestone: $MILESTONE_NAME"
echo "## Project: $PROJECT_NAME"
echo ""

# Filter to non-completed issues
ISSUES_JSON=$(echo "$RESPONSE" | jq '[.data.projectMilestone.issues.nodes[] | select(.state.name != "Done" and .state.name != "Canceled")]')
ISSUE_COUNT=$(echo "$ISSUES_JSON" | jq 'length')

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "No open issues in this milestone."
  exit 0
fi

# Cap at max workers
WORKER_COUNT=$ISSUE_COUNT
if [ "$WORKER_COUNT" -gt "$MAX_WORKERS" ]; then
  echo "Warning: $ISSUE_COUNT issues found, capping at $MAX_WORKERS workers"
  WORKER_COUNT=$MAX_WORKERS
  ISSUES_JSON=$(echo "$ISSUES_JSON" | jq ".[:$MAX_WORKERS]")
fi

echo "Issues to work on ($WORKER_COUNT):"
echo "$ISSUES_JSON" | jq -r '.[] | "  - \(.identifier): \(.title) [\(.state.name)]"'
echo ""

# Find start-work.sh: check repo-local .agents first, then global skills
START_WORK=""
for candidate in \
  "$REPO_ROOT/.agents/skills/working-on-linear-issues/scripts/start-work.sh" \
  "$HOME/.config/agents/skills/working-on-linear-issues/scripts/start-work.sh"; do
  if [ -f "$candidate" ]; then
    START_WORK="$candidate"
    break
  fi
done

if [ -z "$START_WORK" ]; then
  echo "Error: Could not find start-work.sh (checked repo .agents/ and global ~/.config/agents/skills/)"
  exit 1
fi

# Create orchestrator directory
MILESTONE_SLUG=$(echo "$MILESTONE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-30)
MILESTONE_DIR="$ORCHESTRATOR_DIR/$MILESTONE_SLUG"
mkdir -p "$MILESTONE_DIR/logs"

# Save issues JSON for status script
echo "$ISSUES_JSON" > "$MILESTONE_DIR/issues.json"
echo "$MILESTONE_ID" > "$MILESTONE_DIR/milestone-id"
echo "$MILESTONE_NAME" > "$MILESTONE_DIR/milestone-name"

# Create worktrees for each issue
echo "Creating worktrees..."

for i in $(seq 0 $((WORKER_COUNT - 1))); do
  ISSUE_ID=$(echo "$ISSUES_JSON" | jq -r ".[$i].identifier")
  echo ""
  echo "--- Setting up $ISSUE_ID ---"
  bash "$START_WORK" "$ISSUE_ID" 2>&1 | tail -5
done

# Write issue context files into each worktree
echo ""
echo "Writing issue context to worktrees..."
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  ISSUE_ID=$(echo "$ISSUES_JSON" | jq -r ".[$i].identifier")
  ISSUE_TITLE=$(echo "$ISSUES_JSON" | jq -r ".[$i].title")
  ISSUE_DESC=$(echo "$ISSUES_JSON" | jq -r ".[$i].description // \"No description\"")
  ISSUE_URL=$(echo "$ISSUES_JSON" | jq -r ".[$i].url")

  WORKTREE_NAME=$(echo "$ISSUE_ID" | tr '[:lower:]' '[:upper:]')
  WORKTREE_PATH="$WORKTREES_DIR/$WORKTREE_NAME"

  if [ -d "$WORKTREE_PATH" ]; then
    mkdir -p "$WORKTREE_PATH/.orchestrator"
    cat > "$WORKTREE_PATH/.orchestrator/ISSUE.md" <<EOF
# $ISSUE_ID: $ISSUE_TITLE

**URL:** $ISSUE_URL
**Milestone:** $MILESTONE_NAME
**Project:** $PROJECT_NAME

## Description

$ISSUE_DESC

## Instructions

You are an autonomous coding agent working in this git worktree for issue $ISSUE_ID.
Follow the issue description above as your PRD.
Make minimal, focused changes.
Run typecheck and lint commands before finishing (check AGENTS.md for repo-specific commands).
Commit changes to the existing branch.
If blocked, write a BLOCKED note to .orchestrator/status.md and stop.
EOF
    echo "  ✓ $ISSUE_ID context written"
  else
    echo "  ✗ $ISSUE_ID worktree not found at $WORKTREE_PATH"
  fi
done

# Create tmux session
SESSION_NAME="ms-${MILESTONE_SLUG}"

# Kill existing session if present
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

echo ""
echo "Creating tmux session: $SESSION_NAME"

# Window 0: Planner/Dashboard
tmux new-session -d -s "$SESSION_NAME" -n "planner" -c "$REPO_ROOT"
tmux set-option -t "$SESSION_NAME" remain-on-exit on

# Split planner window: top = status, bottom = shell
tmux split-window -t "$SESSION_NAME:planner" -v -c "$REPO_ROOT"

# Top pane: status dashboard
tmux send-keys -t "$SESSION_NAME:planner.0" "watch -n 30 bash $SCRIPT_DIR/milestone-status.sh $MILESTONE_SLUG" Enter

# Bottom pane: useful info
tmux send-keys -t "$SESSION_NAME:planner.1" "echo '=== Milestone: $MILESTONE_NAME ===' && echo 'Workers: $WORKER_COUNT issues' && echo '' && echo 'Ctrl-b w  = list windows' && echo 'Ctrl-b n  = next window (workers)' && echo 'Ctrl-b z  = zoom pane' && echo 'Ctrl-b d  = detach'" Enter

# Create worker windows (up to 6 panes per window)
PANES_PER_WINDOW=6
WINDOW_NUM=1
PANE_IN_WINDOW=0

for i in $(seq 0 $((WORKER_COUNT - 1))); do
  ISSUE_ID=$(echo "$ISSUES_JSON" | jq -r ".[$i].identifier")
  WORKTREE_NAME=$(echo "$ISSUE_ID" | tr '[:lower:]' '[:upper:]')
  WORKTREE_PATH="$WORKTREES_DIR/$WORKTREE_NAME"

  if [ "$PANE_IN_WINDOW" -eq 0 ]; then
    # Create new window
    tmux new-window -t "$SESSION_NAME" -n "workers-$WINDOW_NUM" -c "$WORKTREE_PATH"
    PANE_TARGET="$SESSION_NAME:workers-$WINDOW_NUM.0"
  else
    # Split existing window
    tmux split-window -t "$SESSION_NAME:workers-$WINDOW_NUM" -c "$WORKTREE_PATH"
    PANE_TARGET="$SESSION_NAME:workers-$WINDOW_NUM.$PANE_IN_WINDOW"
  fi

  # Set pane title
  tmux select-pane -t "$PANE_TARGET" -T "$ISSUE_ID"

  # Log pane output
  tmux pipe-pane -t "$PANE_TARGET" -o "cat >> $MILESTONE_DIR/logs/$ISSUE_ID.log"

  # Launch amp in the pane
  ISSUE_CONTEXT="$WORKTREE_PATH/.orchestrator/ISSUE.md"
  if [ -f "$ISSUE_CONTEXT" ]; then
    tmux send-keys -t "$PANE_TARGET" "amp --no-ide -m $AMP_MODE $DANGEROUSLY_ALLOW_ALL" Enter
    sleep 1
    # Send the issue context as the first message
    PROMPT="Execute the task described in .orchestrator/ISSUE.md — read it first, then implement the changes. When done, commit your work."
    tmux send-keys -t "$PANE_TARGET" "$PROMPT" Enter
  else
    tmux send-keys -t "$PANE_TARGET" "echo 'ERROR: No issue context found at $ISSUE_CONTEXT'" Enter
  fi

  PANE_IN_WINDOW=$((PANE_IN_WINDOW + 1))
  if [ "$PANE_IN_WINDOW" -ge "$PANES_PER_WINDOW" ]; then
    # Tile the panes evenly
    tmux select-layout -t "$SESSION_NAME:workers-$WINDOW_NUM" tiled
    WINDOW_NUM=$((WINDOW_NUM + 1))
    PANE_IN_WINDOW=0
  fi
done

# Tile the last worker window if it has panes
if [ "$PANE_IN_WINDOW" -gt 0 ]; then
  tmux select-layout -t "$SESSION_NAME:workers-$WINDOW_NUM" tiled
fi

# Select planner window
tmux select-window -t "$SESSION_NAME:planner"

echo ""
echo "============================================="
echo "  tmux session created: $SESSION_NAME"
echo "  Workers: $WORKER_COUNT"
echo "  Mode: $AMP_MODE"
echo "============================================="
echo ""
echo "Attach with:"
echo "  tmux attach -t $SESSION_NAME"
echo ""
echo "Or if already in tmux:"
echo "  tmux switch-client -t $SESSION_NAME"

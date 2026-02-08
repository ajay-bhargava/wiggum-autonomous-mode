#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/linear-helpers.sh"

MILESTONE_SLUG="$1"
FORCE="${2:-}"

if [ -z "$MILESTONE_SLUG" ]; then
  echo "Usage: cleanup-milestone.sh <MILESTONE_SLUG> [--force]"
  echo ""
  echo "Active milestones:"
  if [ -d "$ORCHESTRATOR_DIR" ]; then
    ls -1 "$ORCHESTRATOR_DIR" 2>/dev/null || echo "  (none)"
  else
    echo "  (none)"
  fi
  exit 1
fi

MILESTONE_DIR="$ORCHESTRATOR_DIR/$MILESTONE_SLUG"

if [ ! -d "$MILESTONE_DIR" ]; then
  echo "Error: Milestone directory not found: $MILESTONE_DIR"
  exit 1
fi

MILESTONE_NAME=$(cat "$MILESTONE_DIR/milestone-name" 2>/dev/null || echo "$MILESTONE_SLUG")
ISSUES_JSON="$MILESTONE_DIR/issues.json"
SESSION_NAME="ms-${MILESTONE_SLUG}"

echo ""
echo "## Cleanup: $MILESTONE_NAME"
echo ""

# Kill tmux session
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Killing tmux session: $SESSION_NAME"
  tmux kill-session -t "$SESSION_NAME"
  echo "  ✓ Session killed"
else
  echo "  No tmux session found: $SESSION_NAME"
fi

# Remove worktrees
if [ -f "$ISSUES_JSON" ]; then
  echo ""
  echo "Removing worktrees..."
  jq -r '.[].identifier' "$ISSUES_JSON" | while read -r ISSUE_ID; do
    WORKTREE_NAME=$(echo "$ISSUE_ID" | tr '[:lower:]' '[:upper:]')
    WORKTREE_PATH="$WORKTREES_DIR/$WORKTREE_NAME"

    if [ -d "$WORKTREE_PATH" ]; then
      # Check for uncommitted changes
      DIRTY=$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null | head -1)
      if [ -n "$DIRTY" ] && [ "$FORCE" != "--force" ]; then
        echo "  ⚠️  $ISSUE_ID has uncommitted changes (use --force to override)"
      else
        git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || rm -rf "$WORKTREE_PATH"
        echo "  ✓ $ISSUE_ID worktree removed"
      fi
    else
      echo "  — $ISSUE_ID (no worktree)"
    fi
  done

  git worktree prune 2>/dev/null || true
fi

# Remove orchestrator data
echo ""
echo "Removing orchestrator data..."
rm -rf "$MILESTONE_DIR"
echo "  ✓ $MILESTONE_DIR removed"

echo ""
echo "Cleanup complete."

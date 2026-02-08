#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/linear-helpers.sh"

MILESTONE_SLUG="$1"

if [ -z "$MILESTONE_SLUG" ]; then
  echo "Usage: milestone-status.sh <MILESTONE_SLUG>"
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

echo ""
echo "## Milestone Status: $MILESTONE_NAME"
echo "## $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "| Issue | Title | Worktree | Branch | Last Commit | Log Size |"
echo "|-------|-------|----------|--------|-------------|----------|"

if [ ! -f "$ISSUES_JSON" ]; then
  echo "| — | No issues.json found | — | — | — | — |"
  exit 0
fi

jq -r '.[].identifier' "$ISSUES_JSON" | while read -r ISSUE_ID; do
  TITLE=$(jq -r ".[] | select(.identifier == \"$ISSUE_ID\") | .title" "$ISSUES_JSON" | cut -c1-40)
  WORKTREE_NAME=$(echo "$ISSUE_ID" | tr '[:lower:]' '[:upper:]')
  WORKTREE_PATH="$WORKTREES_DIR/$WORKTREE_NAME"

  if [ -d "$WORKTREE_PATH" ]; then
    WT_STATUS="✓"
    BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null || echo "—")
    LAST_COMMIT=$(git -C "$WORKTREE_PATH" log -1 --oneline --no-decorate 2>/dev/null | cut -c1-35 || echo "—")
  else
    WT_STATUS="✗"
    BRANCH="—"
    LAST_COMMIT="—"
  fi

  LOG_FILE="$MILESTONE_DIR/logs/$ISSUE_ID.log"
  if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(du -h "$LOG_FILE" | cut -f1)
  else
    LOG_SIZE="—"
  fi

  echo "| $ISSUE_ID | $TITLE | $WT_STATUS | $BRANCH | $LAST_COMMIT | $LOG_SIZE |"
done

# Check for BLOCKED statuses
echo ""
jq -r '.[].identifier' "$ISSUES_JSON" | while read -r ISSUE_ID; do
  WORKTREE_NAME=$(echo "$ISSUE_ID" | tr '[:lower:]' '[:upper:]')
  WORKTREE_PATH="$WORKTREES_DIR/$WORKTREE_NAME"
  STATUS_FILE="$WORKTREE_PATH/.orchestrator/status.md"
  if [ -f "$STATUS_FILE" ] && grep -qi "BLOCKED" "$STATUS_FILE" 2>/dev/null; then
    echo "⚠️  $ISSUE_ID is BLOCKED:"
    head -3 "$STATUS_FILE"
    echo ""
  fi
done

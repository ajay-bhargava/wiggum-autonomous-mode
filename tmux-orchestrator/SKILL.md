---
name: tmux-orchestrator
description: Orchestrate parallel amp workers across Linear milestone issues using tmux + git worktrees. Use when asked to run multiple issues in parallel, start a milestone session, or orchestrate worktree-based development.
---

# tmux-orchestrator Skill

Orchestrate parallel `amp` workers across Linear project milestone issues using tmux sessions + git worktrees.

## Prerequisites Gate

**Before running any script**, verify the repo has a Linear API key:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
HAS_KEY=false
for f in "$REPO_ROOT/.env.local" "$REPO_ROOT/.env"; do
  [ -f "$f" ] && grep -qE '^LINEAR_API_KEY=' "$f" && HAS_KEY=true && break
done
if [ "$HAS_KEY" != "true" ]; then
  echo "ERROR: No LINEAR_API_KEY found in .env.local or .env — this skill requires Linear integration."
  exit 1
fi
```

If no `LINEAR_API_KEY` is found in the repo's `.env.local` or `.env`, **do not proceed**. Inform the user that this skill requires a `LINEAR_API_KEY` to be set in the repository's environment file.

## Architecture

```
Linear Project
  └── Milestone (Subplanner grouping)
       ├── Issue BAT-101 → worktree → tmux pane → amp worker
       ├── Issue BAT-102 → worktree → tmux pane → amp worker
       └── Issue BAT-103 → worktree → tmux pane → amp worker
```

## Workflow

### 1. List Projects

```bash
./scripts/list-projects.sh
```

### 2. List Milestones for a Project

```bash
./scripts/list-milestones.sh <PROJECT_ID>
```

### 3. Start a Milestone Session

This is the main entrypoint. It:
1. Fetches milestone issues from Linear
2. Creates git worktrees for each issue (via existing `start-work.sh`)
3. Creates a tmux session with a dashboard + worker panes
4. Launches `amp` in each worker pane with issue context

```bash
./scripts/start-milestone.sh <MILESTONE_ID> [--max-workers N] [--mode rush|smart|deep]
```

Options:
- `--max-workers N`: Limit concurrent workers (default: 6)
- `--mode`: amp agent mode for workers (default: smart)

### 4. Check Status

```bash
./scripts/milestone-status.sh <MILESTONE_ID>
```

Or from within the planner tmux window, it runs under `watch` automatically.

### 5. Cleanup

```bash
./scripts/cleanup-milestone.sh <MILESTONE_ID>
```

Removes worktrees and tmux session for a completed milestone.

## tmux Session Layout

- **Window 0 (planner)**: Dashboard with status table + shell
- **Window 1+ (workers)**: Up to 6 panes per window, each running `amp` in a worktree

## Key Commands Inside tmux

- `Ctrl-b w` - list windows
- `Ctrl-b n/p` - next/previous window
- `Ctrl-b o` - cycle panes
- `Ctrl-b q` - show pane numbers
- `Ctrl-b z` - zoom/unzoom pane
- `Ctrl-b d` - detach (session continues in background)
- `tmux attach -t ms-<name>` - reattach

## Prerequisites

- `tmux` installed
- `LINEAR_API_KEY` in `.env.local` or `.env` at the repo root
- `jq` installed

---
name: team-orchestration
description: "Runs a multi-agent tmux orchestration pattern with root planner, subplanners, and workers in visible panes. Use when coordinating parallel worktrees and requiring workers to report status back to the main pane."
---

# Team Orchestration

Establishes a consistent multi-agent workflow in a single tmux window. Use this skill when you need a root planner to split scope into subplanners and spawn visible workers, each running in a dedicated worktree and reporting status back to the main pane.

## When To Use

- Coordinating multiple parallel workers within one tmux window.
- Enforcing a root planner + subplanner + worker structure.
- Requiring explicit status updates sent back to the main pane.
- Requiring worktrees per worker to avoid conflicts.

## Workflow

1. Identify the root planner scope and decide on subplanner slices.
2. Create one worktree per worker using a consistent naming scheme.
3. Split panes in the current tmux window so all workers are visible.
4. Capture the coordinator pane ID: `tmux display-message -p '#{pane_id}'`
5. Write each worker's prompt to a temp file (see Prompt File Pattern below).
6. Launch workers one at a time with 1-second delays between launches.
7. Monitor workers via status reports and pane capture.
8. Merge order: Convex first, Runtime second, Terraform last.

## Prompt File Pattern (REQUIRED)

**NEVER use `tmux send-keys` with inline multi-line prompts.** Quotes, newlines, and special characters get garbled, and Amp CLI may not be ready when keys arrive.

**ALWAYS write prompt files first, then launch with stdin redirection:**

```bash
# 1. Pre-create a thread to capture the ID
THREAD_ID=$(amp threads new --no-color 2>/dev/null)
echo "Worker NAME thread: $THREAD_ID" >> /tmp/orchestration-threads.txt

# 2. Write the prompt file (include @@thread-ids for provenance)
cat > /tmp/worker-NAME.md << PROMPT_EOF
# Worker Task: <description>

## Provenance

Parent thread: @@$PLANNER_THREAD_ID
Sibling workers:
- worker-other: @@$TID_OTHER
Full manifest: /tmp/orchestration-threads.txt
Use read_thread on any @@ above to get context from parent or siblings.

Your coordinator is in tmux pane %NN. Report status with:
tmux send-keys -t %NN "STATUS NAME: <your message>" C-m

When you finish all work, report:
tmux send-keys -t %NN "STATUS NAME: work complete" C-m

## Task Details

<detailed instructions here, markdown formatting is fine>
PROMPT_EOF

# 3. Launch amp in the target pane, continuing the pre-created thread
tmux send-keys -t %TARGET "cd /path/to/worktree && amp threads continue $THREAD_ID --dangerously-allow-all < /tmp/worker-NAME.md" C-m
```

### Why This Works

- No shell escaping issues — the prompt is in a file, not inline
- No race condition — amp reads stdin after it starts
- Prompts can be arbitrarily complex with full markdown formatting
- Prompt files are inspectable for debugging
- Thread IDs are known upfront for monitoring, `read_thread`, and `find_thread`

### Thread ID Capture

Pre-creating threads with `amp threads new` gives you the thread ID before launch. Store all IDs in a manifest file:

```bash
# Create manifest
echo "# Orchestration Threads - $(date)" > /tmp/orchestration-threads.txt

# For each worker, pre-create and record
THREAD_WORKER1=$(amp threads new --no-color 2>/dev/null)
echo "worker1: $THREAD_WORKER1" >> /tmp/orchestration-threads.txt

THREAD_WORKER2=$(amp threads new --no-color 2>/dev/null)
echo "worker2: $THREAD_WORKER2" >> /tmp/orchestration-threads.txt
```

This enables:
- **Monitoring**: `amp threads markdown $THREAD_ID` to see full thread output
- **Cross-referencing**: Use `read_thread` tool to pull context from a worker thread
- **Debugging**: Know exactly which thread each pane is running
- **Labels**: Use `--label worker-name` when continuing to tag threads for search

### Worker Prompt Template

Every worker prompt MUST include provenance (parent + siblings), status reporting, and the task:

```markdown
# Worker Task: <short description>

## Provenance

Parent thread: @@T-planner-thread-id
Sibling workers:
- worker-api: @@T-sibling-api-thread-id
- worker-db: @@T-sibling-db-thread-id
Full manifest: /tmp/orchestration-threads.txt

Use `read_thread` on any @@ above to get context from parent or siblings.

Your coordinator is in tmux pane %NN. Report status with:
tmux send-keys -t %NN "STATUS <ID>: <your message>" C-m

When you finish all work, report:
tmux send-keys -t %NN "STATUS <ID>: work complete" C-m

## TASK

<detailed task description>
```

## Thread Provenance

Every thread in the orchestration tree must know where it came from. Use the `@@<thread-id>` notation to pass parent thread references into child prompts. This creates a provenance chain: **coordinator → planner → worker**.

### How It Works

1. Each agent's Amp thread ID is in its environment as `Amp Thread URL` (format: `https://ampcode.com/threads/T-xxx...`).
2. Extract the `T-...` portion and pass it to child prompts using `@@<thread-id>`.
3. Children can use `read_thread` on the `@@` reference to pull full context from the parent.

### Provenance in the Manifest

The manifest at `/tmp/orchestration-threads.txt` tracks the full hierarchy:

```bash
# Orchestration - 2026-02-08
coordinator: T-aaa-coordinator-thread-id
  planner-runtime: T-bbb-planner-thread-id  (parent: T-aaa-coordinator-thread-id)
    worker-api: T-ccc-worker-thread-id       (parent: T-bbb-planner-thread-id)
    worker-db: T-ddd-worker-thread-id        (parent: T-bbb-planner-thread-id)
  planner-infra: T-eee-planner-thread-id     (parent: T-aaa-coordinator-thread-id)
    worker-tf: T-fff-worker-thread-id        (parent: T-eee-planner-thread-id)
```

### Including Provenance in Prompts

Every prompt file MUST include a provenance block with `@@<thread-id>`. Since all thread IDs are pre-created before any worker launches, you can inject sibling IDs directly — workers don't need to discover each other at runtime.

```markdown
## Provenance

Parent thread: @@T-planner-thread-id
Sibling workers:
- worker-api: @@T-aaa-worker-api-thread-id
- worker-db: @@T-bbb-worker-db-thread-id
Full manifest: /tmp/orchestration-threads.txt

To get context from the parent planner, use `read_thread` on the parent @@.
To coordinate with a sibling, use `read_thread` on their @@ to see what they've done.
```

### Cross-Worker Communication

Workers can interact by reading each other's threads with `@@<sibling-thread-id>`:

- **Check sibling progress**: `read_thread` on a sibling's `@@` to see if they've completed a dependency
- **Avoid conflicts**: Read a sibling's thread to see what files they've modified
- **Share context**: A worker that produces an API schema can tell its sibling to `read_thread` its `@@` for the output

Because all IDs are in every prompt, no runtime discovery is needed. Workers already know who their siblings are.

Workers can also:
- Use `find_thread` with `cluster_of:<parent-thread-id>` to discover the full orchestration cluster
- Reference the manifest at `/tmp/orchestration-threads.txt` for the complete tree

## Startup Sequence

Follow this exact order:

```bash
# 1. Enable mouse for pane resizing
tmux set -g mouse on

# 2. Get coordinator pane ID and thread ID (for provenance)
COORDINATOR=$(tmux display-message -p '#{pane_id}')
# Extract your own thread ID from the Amp Thread URL in your environment
# (available as "Amp Thread URL: https://ampcode.com/threads/T-xxx...")
PLANNER_THREAD_ID="T-your-thread-id-here"  # Replace with actual thread ID

# 3. Create worktrees
git worktree add ../project-worker1 HEAD
git worktree add ../project-worker2 HEAD

# 4. Split panes (all visible in current window)
tmux split-window -h
tmux split-window -v
# Arrange as needed: tmux select-layout tiled

# 5. List panes to get IDs
tmux list-panes -F '#{pane_id} #{pane_current_path}'

# 6. Pre-create threads and record IDs with provenance
echo "# Orchestration $(date)" > /tmp/orchestration-threads.txt
echo "coordinator: $PLANNER_THREAD_ID" >> /tmp/orchestration-threads.txt
TID1=$(amp threads new --no-color 2>/dev/null)
echo "  worker-one: $TID1  (parent: $PLANNER_THREAD_ID)" >> /tmp/orchestration-threads.txt
TID2=$(amp threads new --no-color 2>/dev/null)
echo "  worker-two: $TID2  (parent: $PLANNER_THREAD_ID)" >> /tmp/orchestration-threads.txt

# 7. Write ALL prompt files BEFORE launching any worker
cat > /tmp/worker-one.md << 'PROMPT_EOF'
...
PROMPT_EOF

cat > /tmp/worker-two.md << 'PROMPT_EOF'
...
PROMPT_EOF

# 8. Launch workers with 1-second delays, using pre-created thread IDs
tmux send-keys -t %PANE1 "cd /path/to/worktree1 && amp threads continue $TID1 --dangerously-allow-all < /tmp/worker-one.md" C-m
sleep 1
tmux send-keys -t %PANE2 "cd /path/to/worktree2 && amp threads continue $TID2 --dangerously-allow-all < /tmp/worker-two.md" C-m
```

## Status Reporting

Workers report status back to the coordinator pane using:

```bash
tmux send-keys -t %COORDINATOR "STATUS <ID>: <message>" C-m
```

The coordinator sees these as text lines appearing in its pane. Standard markers:
- `STATUS <ID>: starting <task>` — work begun
- `STATUS <ID>: <progress update>` — intermediate progress
- `STATUS <ID>: work complete` — all done

## Monitoring Workers

Check worker progress by capturing recent pane output:

```bash
# Last 20 lines from a worker pane
tmux capture-pane -t %PANE -p -S -20

# Check if amp is still running in a pane
tmux list-panes -F '#{pane_id} #{pane_current_command}'
```

## Failure Recovery

If a worker pane is idle (no amp process running) but work is incomplete:

```bash
# Check if amp is running
tmux list-panes -F '#{pane_id} #{pane_current_command}' | grep %PANE

# Look up the thread ID from the manifest
cat /tmp/orchestration-threads.txt

# Re-launch using the SAME prompt file and thread ID (continues the conversation)
tmux send-keys -t %PANE "cd /path/to/worktree && amp threads continue $THREAD_ID --dangerously-allow-all < /tmp/worker-NAME.md" C-m
```

The prompt file and thread ID persist in `/tmp/orchestration-threads.txt` so re-launches continue the same thread rather than starting fresh.

## Cleanup

When all workers are done:

```bash
# 1. Kill worker panes (not the coordinator pane)
tmux kill-pane -t %PANE1
tmux kill-pane -t %PANE2

# 2. Merge worktrees back (follow merge order)
cd /path/to/main
git merge --no-ff worktree-branch

# 3. Remove worktrees
git worktree remove ../project-worker1
git worktree remove ../project-worker2

# 4. Clean up prompt files
rm -f /tmp/worker-*.md
```

## Guardrails

- All worker panes must stay visible in the current tmux window.
- No background workers or hidden tmux sessions.
- Use Bun for installs (`bun add`, `bun install`), never npm.
- If a worker needs to spawn a sub-worker, it must use a new visible pane in the same tmux window.
- Enable mouse resizing with `tmux set -g mouse on` so pane heights can be dragged.
- **Never use inline `tmux send-keys` for multi-line prompts** — always use prompt files.

## Quick Reference

```bash
# Get current pane ID
tmux display-message -p '#{pane_id}'

# List all panes with IDs and paths
tmux list-panes -F '#{pane_id} #{pane_current_command} #{pane_current_path}'

# Split pane horizontally / vertically
tmux split-window -h
tmux split-window -v

# Tile all panes evenly
tmux select-layout tiled

# Pre-create thread and record ID
TID=$(amp threads new --no-color 2>/dev/null)
echo "worker-name: $TID" >> /tmp/orchestration-threads.txt

# Write prompt and launch worker with thread ID
cat > /tmp/worker-NAME.md << 'PROMPT_EOF'
<prompt content>
PROMPT_EOF
tmux send-keys -t %PANE "cd /path && amp threads continue $TID --dangerously-allow-all < /tmp/worker-NAME.md" C-m

# Check worker output (last 20 lines)
tmux capture-pane -t %PANE -p -S -20

# Send status to coordinator
tmux send-keys -t %COORD "STATUS ID: message" C-m

# Kill a pane
tmux kill-pane -t %PANE

# Clean up worktree
git worktree remove ../worktree-name

# View full thread output
amp threads markdown $THREAD_ID

# List all orchestration threads
cat /tmp/orchestration-threads.txt

# Clean up prompt files and manifest
rm -f /tmp/worker-*.md /tmp/orchestration-threads.txt
```

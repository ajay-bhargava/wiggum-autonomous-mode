---
name: ralph-mode
description: Executes PRD-driven autonomous development on current branch using Amp handoffs. Use when asked to run Ralph Mode, execute a PRD, or autonomously implement user stories with iteration-based handoffs.
---

# Ralph Mode (Branch)

PRD-driven autonomous execution on the **current branch** using Amp handoffs. Each iteration runs in a fresh thread to prevent context degradation.

## Branch Naming

- **Linear issue referenced**: Use Linear's branch name format (e.g., `team-123-feature-title`)
- **No Linear issue**: Use `autonomous/feature-name`

## Modes

### Planning Mode
Interactive PRD creation with the user. Use when no prd.json exists or user asks to plan.

**Turn-by-turn Q&A process:**

1. **Understand the feature** — Ask clarifying questions:
   - What problem does this solve?
   - Who is the user?
   - What are the key workflows?
   - Any technical constraints or preferences?
   - What does "done" look like?

2. **Scope the work** — Break into small stories, ask:
   - Does this ordering make sense?
   - Any dependencies I'm missing?
   - Should any stories be split further?

3. **Define acceptance criteria** — For each story, confirm:
   - What commands verify success? (typecheck, tests, etc.)
   - Any browser verification needed?

4. **Generate artifacts** — Only after user confirms scope:
   - Create `docs/autonomous/<branch-name>/` directory
   - Wipe contents if it exists (fresh start)
   - Create prd.json, progress.txt, prompt.md in that folder

5. **User approves** — Show generated prd.json, get explicit approval before execution

### Execution Mode
Autonomous story completion with handoffs. Use when prd.json exists and user asks to execute.

## Artifacts

All artifacts live in `docs/autonomous/<branch-name>/`:

### docs/autonomous/<branch-name>/prd.json

```json
{
  "project": "project-name",
  "branchName": "autonomous/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short title",
      "description": "As a [user], I need [what] so that [why]",
      "acceptanceCriteria": [
        "Specific verifiable criterion",
        "Typecheck passes: <command>"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### docs/autonomous/<branch-name>/progress.txt

```markdown
# Progress Log

## Iteration Counter
current_iteration: 1
max_iterations: 15

## Codebase Patterns

(Consolidate reusable patterns here as they are discovered)

---

## Execution Log

(Entries appended below as iterations complete)
```

### docs/autonomous/<branch-name>/prompt.md

Contains execution instructions for each iteration. Template provided below.

## Execution Steps

**FOLLOW THESE STEPS IN ORDER:**

1. **Read progress.txt FIRST** — Check "Codebase Patterns" section at top
2. **Read prd.json** — Find current state
3. **Check iteration limit** — If `current_iteration >= max_iterations`, output `<promise>COMPLETE</promise>` and STOP
4. **Check branch** — Ensure on correct branch from prd.json, checkout if needed
5. **Pick next story** — First story where `passes: false` (lowest priority number)
6. **Implement ONE story** — Complete all acceptance criteria
7. **Run quality checks** — Typecheck/tests from acceptance criteria
8. **Update AGENTS.md** — If patterns discovered, add to relevant AGENTS.md
9. **Commit** — `git add -A && git commit -m "feat: [US-XXX] - title"`
10. **Update prd.json** — Set `passes: true`, add notes
11. **Update progress.txt** — Increment counter, append log entry
12. **Check completion**:
    - If ALL stories pass → output `<promise>COMPLETE</promise>` and STOP
    - If `current_iteration >= max_iterations` → output `<promise>COMPLETE</promise>` and STOP
    - Otherwise → handoff to fresh thread

## Progress Log Entry Format

APPEND to progress.txt (never replace existing content):

```markdown
---

## YYYY-MM-DD | US-XXX | T-<thread-id>
**Changes:** Brief description of what was implemented
**Files:** file1.py, file2.py
**Learnings:** Patterns discovered for future iterations
```

## Handoff Format

When handing off, use this goal:
```
Execute Ralph Mode for <feature>. Read docs/autonomous/<branch-name>/prompt.md for instructions.
```

## Completion Signals

Output `<promise>COMPLETE</promise>` when:
- All stories have `passes: true`
- `current_iteration >= max_iterations`
- Unrecoverable error (document in progress.txt first)

## Story Sizing Guidelines

**Right-sized (one iteration):**
- Add a Pydantic model
- Create a single endpoint
- Write unit tests for one function
- Create a single file following existing patterns

**Too large (split these):**
- "Implement full pipeline" → 5+ stories
- "Add complete CRUD" → 4 stories (create, read, update, delete)
- "Build entire feature" → Break into layers/components

## Dependency Ordering

```
1. Types/schemas/models
2. Core logic/utilities
3. API endpoints using logic
4. Integration tests
5. Deploy/smoke tests
6. Documentation/scripts
```

## Browser Verification (Frontend Stories)

For any story that changes UI, include browser verification in acceptance criteria:

```
"Verify in browser using agent-browser"
```

Use `agent-browser` CLI for verification:
```bash
# Take snapshot and screenshot
npx agent-browser open http://localhost:3000/page
npx agent-browser snapshot
npx agent-browser screenshot

# Interact with elements
npx agent-browser click "button:Submit"
npx agent-browser fill "input:Email" "test@example.com"
```

A frontend story is NOT complete until browser verification passes.

## Pattern Consolidation

If you discover a reusable pattern during implementation:
1. Add it to "## Codebase Patterns" section at TOP of progress.txt
2. If generally useful, also add to nearest AGENTS.md

Only add general patterns, not story-specific details.

## Quality Requirements

- ALL commits must pass typecheck
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing patterns in codebase
- Run acceptance criteria checks before marking story complete

## prompt.md Template

Create this file at docs/autonomous/<branch-name>/prompt.md:

```markdown
# Ralph Mode: <Feature Name>

You are executing Ralph Mode via Amp handoffs. Follow these rules strictly.

## Execution Steps (In Order)

1. **Read progress.txt FIRST** — Check "Codebase Patterns" section at top
2. **Read prd.json** — Find current state
3. **Check iteration limit** — If `current_iteration >= max_iterations`, output `<promise>COMPLETE</promise>` and STOP
4. **Check branch** — Ensure on `<branch-name>`, checkout if needed
5. **Pick next story** — First story where `passes: false` (lowest priority number)
6. **Implement ONE story** — Complete all acceptance criteria
7. **Run quality checks** — Typecheck/tests from acceptance criteria
8. **Update AGENTS.md** — If patterns discovered, add to relevant AGENTS.md
9. **Commit** — `git add -A && git commit -m "feat: [US-XXX] - title"`
10. **Update prd.json** — Set `passes: true`, add notes
11. **Update progress.txt** — Increment counter, append log entry
12. **Check completion**:
    - If ALL stories pass → output `<promise>COMPLETE</promise>` and STOP
    - If `current_iteration >= max_iterations` → output `<promise>COMPLETE</promise>` and STOP
    - Otherwise → handoff to fresh thread

## Handoff Format

When handing off, use this goal:
```
Execute Ralph Mode for <feature>. Read docs/autonomous/<branch-name>/prompt.md for instructions.
```

## Progress Report Format

APPEND to progress.txt (never replace existing content):

```markdown
---

## YYYY-MM-DD | US-XXX | T-<thread-id>
**Changes:** Brief description of what was implemented
**Files:** file1.py, file2.py
**Learnings:** Patterns discovered for future iterations
```

## Stop Conditions

Output `<promise>COMPLETE</promise>` when:
- All stories have `passes: true`
- `current_iteration >= max_iterations`
- Unrecoverable error (document in progress.txt first)

## Reference Files

| File | Purpose |
|------|---------|
| <file> | <purpose> |

## Quality Requirements

- ALL commits must pass typecheck
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing patterns in codebase
```

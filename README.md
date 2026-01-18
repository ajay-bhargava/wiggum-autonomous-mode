# Amp Skills

Custom skills for [Amp](https://ampcode.com) that enable PRD-driven autonomous development.

## Skills

| Skill | Description |
|-------|-------------|
| **ralph-mode** | Autonomous development on current branch using Amp handoffs |
| **ralph-mode-worktree** | Same as above, but in a separate git worktree for isolation |

## Installation

Clone this repo to Amp's global skills directory:

```bash
# Remove existing skills directory if present (backup first if needed)
mv ~/.config/agents/skills ~/.config/agents/skills.bak

# Clone
git clone <repo-url> ~/.config/agents/skills

# Or if you already have skills, clone elsewhere and symlink
git clone <repo-url> ~/src/amp-skills
ln -s ~/src/amp-skills/ralph-mode ~/.config/agents/skills/ralph-mode
ln -s ~/src/amp-skills/ralph-mode-worktree ~/.config/agents/skills/ralph-mode-worktree
```

## Usage

In any Amp thread, invoke by name:

```
Run Ralph Mode to implement <feature>
```

Or for worktree mode:

```
Run Ralph Mode in a worktree to implement <feature>
```

See individual `SKILL.md` files for detailed documentation.

## Structure

```
~/.config/agents/skills/
├── ralph-mode/
│   └── SKILL.md
└── ralph-mode-worktree/
    └── SKILL.md
```

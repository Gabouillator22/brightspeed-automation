# /pr

Create a pull request for the current branch.

## Usage
```
/pr
```

## What this does
1. Runs `/review` — blocks if VERDICT is BLOCK.
2. Runs `git diff main...HEAD` to summarize all changes.
3. Creates a PR via `gh pr create` with:
   - Title: derived from the commit messages.
   - Body: bullet summary of changes + test plan checklist.
4. Prints the PR URL.

## PR body template
```markdown
## Summary
- [what changed, one bullet per logical change]

## NCDOT compliance
- [ ] Label formats verified against spec
- [ ] No hardcoded paths
- [ ] Linework standards (width 0.5, LINETYPE GENERATION, layer colors)
- [ ] Text heights correct (5.0 / 6.0)

## Test plan
- [ ] Loaded in AutoCAD Map 3D 2027
- [ ] BSINSTALLCHECK passes
- [ ] Relevant BS* commands tested on sample drawing
- [ ] BSAUDIT passes with no CRITICAL findings

🤖 Generated with Claude Code
```

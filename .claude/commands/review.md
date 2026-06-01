# /review

Run the `code-reviewer` agent on the current staged diff.

## Usage
```
/review
```

## What this does
1. Runs `git diff --cached` to get the staged changes.
2. Delegates to the `code-reviewer` agent with that diff.
3. Prints the CRITICAL / WARNING / SUGGESTION report.
4. If VERDICT is BLOCK, does not proceed — fix issues first, then re-run `/review`.

## When to use
Before every `git commit`. The `pre-commit.sh` hook runs automated checks; `/review` adds the AI judgment layer for things the script cannot catch (semantic issues, NCDOT label correctness, architectural drift).

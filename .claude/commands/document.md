# /document

Sync documentation after code changes land.

## Usage
```
/document
```

## What this does
Delegates to the `doc-writer` agent to:
1. Update `04_documentation/` with any new commands or changed behavior.
2. Update the `AGENTS.md` root brain (command list, layer mapping if changed).
3. Append a one-line note to `04_documentation/SESSION_NOTES.md` dated today.
4. Update nested `AGENTS.md` files in `05_toolkit/lisp/` and `05_toolkit/python/`.

## When to use
After any code change that adds, removes, or modifies a public `BS*` command.

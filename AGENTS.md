# AGENTS.md — Brightspeed Toolkit Brain

> This file and `03_architecture/` are the canonical memory for this project.
> All agents (Claude Code and Codex) read this file. Record decisions here, not in chat.

---

## Project

Brightspeed fiber-optic permit drawings submitted to NCDOT.
Deliverable: NCDOT-compliant permit drawing sets.
High weekly linework volume across multiple active permits.

---

## Architecture

**Two-node setup:**
- **Mac** = orchestration brain — Claude Code, git, file editing, Python scripting.
- **Windows (AutoCAD Map 3D 2027 via Parallels)** = execution node — runs all `BS*` AutoCAD commands.
- Synced via **GitHub** (`brightspeed-automation` private repo).

Code lives in `05_toolkit/`. DWG files live on the Windows local drive and are **never committed**.

---

## Core principle

> Deterministic code (Python + LISP) does ALL geometry. AI orchestrates and verifies only — it never places geometry.

---

## Hard rules

1. **DWG files stay on the local Windows drive.** Never write to a Mac shared path (`/Volumes/`, `//Mac/`, `\\Mac\\`, `Z:\`) — Parallels crashes or corrupts drawings.
2. **Linework standards:** global width `0.5`; enable `LINETYPE GENERATION`; colors come from the **layer**, never manually assigned (`(cons 62 N)` in entmake is a CRITICAL violation).
3. **Layer mapping:**
   - `OVERLASH` → `E-LASH`
   - `NEW STRAND` → `AERIAL FIBER`
   - `UNDERGROUND` → `Buried Fiber in Duct`
4. **Max 25 sheets per permit.** Profiles at the end. Freeze `BORDER` layer in permit sheets.
5. **Text heights:** street names `6.0`; all other labels `5.0`; never scale text down.
6. **No hardcoded absolute paths** in any `.lsp` or `.py` file.
7. **Secrets** (tokens, PATs, passwords) never in committed files. Use `.claude/settings.local.json` (gitignored).

---

## LISP conventions

- Files: `bs_<command>.lsp` in `05_toolkit/lisp/`.
- Load sequence: `APPLOAD bs_loader.lsp` → `BSINSTALLCHECK` → then Brightspeed commands.
- Every public command has a local `*error*` handler that restores sysvar, ends UNDO group, prints message.
- `UNDO _BEGIN` / `UNDO _END` bracket every command (one Ctrl+Z = full undo).
- Use `bs-` helpers from `bs_helpers.lsp` (loaded first by bs_loader.lsp).
- Register new files in `bs_loader.lsp` with `(bs-load-file "bsNEWFILE.lsp")`.

See: `.claude/rules/lisp.md` · `.claude/skills/autolisp-debugger/SKILL.md`

---

## Python conventions

- Deterministic geometry ops only — one module per operation under `05_toolkit/python/`.
- Entry points via `argparse`; `.bat` launchers call `python script.py` (no hard-coded Python path).
- Required packages: `ezdxf`, `lxml`, `pyproj`, `shapely`.
- Every new op requires a test in `05_toolkit/python/tests/`.

See: `.claude/rules/python.md` · `.claude/skills/autocad-map3d/SKILL.md`

---

## Agent roster

| Agent | Model | Job |
|---|---|---|
| `lisp-author` | sonnet | Authors new bs_*.lsp routines |
| `python-author` | sonnet | Writes Python geometry scripts |
| `debugger` | sonnet | Diagnoses LISP + Python bugs |
| `refactorer` | sonnet | Optimizes without changing behavior |
| `code-reviewer` | opus | Reviews diff before commit |
| `test-writer` | sonnet | Golden-file + regression tests |
| `doc-writer` | haiku | Syncs 04_documentation + this file |
| `architect` | opus | Maintains 03_architecture + ADRs |

Agent definitions: `.claude/agents/`

---

## Canonical label formats (NCDOT — state refuses deviations)

| Feature | Label |
|---|---|
| Handhole | `STA XX+XX PL HANDHOLE` |
| Bore pit | `STA XX+XX PL 36"X36" BORE PIT` |
| Pole riser up | `STA XX+XX EX POLE/RISER UP` |
| Pole riser down | `STA XX+XX EX POLE/RISER DOWN` |
| Buried fiber | `HDD BORE [N]' FIBER IN 2" DUCT` |
| Aerial fiber | No footage label |
| MIN DOC | `MIN DOC 60"` (every underground sheet) |

---

## Memory rule

> `AGENTS.md` (this file) and `03_architecture/` ARE the project memory — the ONLY thing that syncs across machines and tools.
> Record significant decisions here or as ADRs in `03_architecture/decisions/`.
> Do NOT record decisions only in chat.

---

## Tool split

- **Claude Code** reads this file + uses `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`.
- **Codex** reads this file (+ nested `AGENTS.md` in `05_toolkit/lisp/` and `05_toolkit/python/`) and `.claude/skills/`.
- Both tools read `AGENTS.md` — it is the authoritative shared brain.

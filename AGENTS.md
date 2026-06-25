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

## Operational toolkit stabilization

The active stabilization target is the loader-driven workflow exposed by
`05_toolkit/lisp/bs_loader.lsp`. Planning, testing, and status reporting
should treat these as the canonical workflow stages:

1. Base road geometry
   - `BSROW`
   - `BSADDTRAP`
   - `BSFILLET-ALL`
   - `BSDRIVE`
   - `BSROWDIMS`
2. Parcel cleanup
   - `BSPARHIDE`
   - `BSPARCELS`
   - `BSPARSNAP`
3. KMZ ingest and conforming
   - `BSKMZ`
   - `BSKMZ-FIBERSNAP`
   - `BSKMZ-HHALIGN`
   - `BSKMZ-AERIALSNAP`
   - `BSKMZ-SNAP`
4. Sheet planning
   - `BSSHEETRECT`
   - `BSSHEETLOAD`
   - `BSSHEETMAKE`
   - `BSSHEETACCEPT`
   - `BSSHEETCLEAR`
   - `BSSHEETKMZ`
   - Python support: `bssheetplan.py`, `bsbuild.py`
5. Annotation and structure callouts
   - `BSCALLOUT`
   - `BSCALLOUT-AUTO`
   - `BSAERIAL`
   - `BSAERIAL-AUTO`
   - `BSCALLOUTS-RUN`
   - `BSCALLOUTS-STRUCTURES`
   - `BSCALLOUTS-BURIED`
   - `BSCALLOUTS-AERIAL`
   - `BSCALLOUTS-AUDIT`
6. Final labeling and QA
   - `BSSTATION`
   - `BSWORKAREA`
   - `BSMINERDOC`
   - `BSAUDIT`
7. Border and final cleanup
   - `BSCLEANRECT`
   - `BSCLEAN`
   - `BSCLEANALL`
   - `BSCLEANMAP`
   - `BSCLEANOUT`
   - `BSCLEANLINES`
   - `BSCLEANTRIMSEL`
   - `BSCLEANBAD`
   - `BSCLEANCLEARMASK`
   - `BSCLEANPICK`
   - `BSCLEANUP`

Compatibility-only aliases remain supported but are not separate
deliverables unless they block the canonical path. This includes
`BSDIMS`, `BSDIM1`, `BSDIMC`, `BSDIAG`, `BSMAP`, `BCMAP`, `BSCLMAP`,
`BSCLEANVP`, `BSCLEANLIMIT`, `TRIMAGE`, `BSCLEANAUTO`, and
`BSCLEANFINAL`.

Canonical cross-tool handshakes:
- Sheet planning: `bssheet_plan.csv` is the primary handoff; generated
  `bssheet_plan.lsp` remains loader-friendly compatibility output.
- KMZ sheet workflow: `bssheet_route_selected.txt` is the planning export
  generated by `BSSHEETKMZ`.
- Parcel extraction: `bsparcels.py` outputs DXF parcel datasets for
  insertion into the drawing workflow.

---

## Memory rule

> `AGENTS.md` (this file) and `03_architecture/` ARE the project memory — the ONLY thing that syncs across machines and tools.
> Record significant decisions here or as ADRs in `03_architecture/decisions/`.
> Do NOT record decisions only in chat.

### Mandatory session update rule

**Every Codex and Claude session that materially tests, fixes, breaks, or validates a command/script MUST update**
`04_documentation/TOOLKIT_STATUS.md` **before ending the session.**

Minimum required detail per update:
- date
- agent/tool name
- command or script name
- status: `working`, `partial`, `broken`, `untested`, or `regressed`
- what was actually tested or changed
- exact failure mode or known limitation, if any
- next action

If a session changes behavior and does not update `04_documentation/TOOLKIT_STATUS.md`, that session is incomplete.

---

## Tool split

- **Claude Code** reads this file + uses `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`.
- **Codex** reads this file (+ nested `AGENTS.md` in `05_toolkit/lisp/` and `05_toolkit/python/`) and `.claude/skills/`.
- Both tools read `AGENTS.md` — it is the authoritative shared brain.

---

## Persistent Agent Status System

- Historical note: a tmux-based experiment existed earlier, but native Windows VS Code terminals are the active target for this project setup.
- Keep any terminal background status work independent from Brightspeed CAD automation logic.
- After changing Codex hooks, remind the user to run `/hooks` in a new or restarted Codex session.
- Do not let multiple agents edit `.codex/hooks.json`, `.codex/hooks/*`, `tools/agent-bg/*`, or related status docs simultaneously.

---

## Windows VS Code Terminal Background Status

- Do not use tmux for this project setup.
- Use `.codex/hooks/set-terminal-bg.ps1` for Codex terminal background state.
- After changing hooks, remind the user to run `/hooks`.
- Keep this isolated from Brightspeed CAD automation scripts.

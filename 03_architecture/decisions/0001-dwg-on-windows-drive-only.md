# 0001 — DWG files must stay on Windows local drive

**Date:** 2026-06-01
**Status:** Accepted
**Deciders:** Gabriel, Claude

## Context
The project runs AutoCAD Map 3D 2027 on Windows inside Parallels on a Mac.
During early testing, drawings opened from Mac shared paths (`/Volumes/`, `Z:\`) caused Parallels to hang or corrupt the DWG on save.

## Decision
All `.dwg` files are stored on the Windows local drive only (`C:\`).
Mac-side tools never write to `.dwg` files directly.
Git never commits `.dwg` files (gitignored).

## Consequences
- DWG files are not version-controlled — they must be backed up separately.
- The Mac orchestration node can read/write `.lsp`, `.py`, `.md` files freely.
- No cross-machine DWG editing is possible without explicit manual copy.

## Alternatives considered
- **Network share (SMB):** Rejected — Parallels SMB performance is too slow for AutoCAD and caused corruption on crash.
- **Git LFS for DWG:** Rejected — DWG is binary; diffs are meaningless; LFS adds operational complexity.

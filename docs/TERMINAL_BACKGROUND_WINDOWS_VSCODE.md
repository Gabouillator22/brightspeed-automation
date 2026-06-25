# Windows VS Code Terminal Background

## Overview

This project uses native Windows PowerShell scripts plus OSC escape sequences to
change the background of each VS Code integrated terminal running a Codex
session.

This implementation is for:

- native Windows
- VS Code integrated terminals
- Codex hooks

It does not use tmux, WSL, Linux shell scripts, or pane styling.

## How it works

The hook scripts are:

- `.codex/hooks/set-terminal-bg.ps1`
- `.codex/hooks/set-terminal-bg-stop.ps1`
- `.codex/hooks/set-terminal-bg-error.ps1`

The normal hook script writes OSC sequences to `CONOUT$` first and may fall
back to stdout for non-Stop usage. The Stop-only script writes OSC to
`CONOUT$` first, then falls back to stderr so stdout can remain valid Stop JSON.

It sets:

- `OSC 2` terminal title, for example `Codex: running`
- `OSC 10` foreground text color
- `OSC 11` terminal background color
- `OSC 110`, `OSC 111`, `OSC 112` for reset

## Lifecycle colors

- `idle` -> dark gray background `#151515`
- `running` -> blue background `#001b3a`
- `completed` -> green background `#003313`
- `input` -> orange background `#3a2400`
- `error` -> red background `#3a0000`
- `reset` -> terminal default colors

Legend:

- Blue = working
- Green = completed
- Orange = input/permission required
- Red = failure/error
- Dark gray = idle

## Hook trust step

After changing hooks, open Codex in this repo and run:

```text
/hooks
```

Approve the project-local hooks.

## Manual test commands

Individual states:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 idle
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 running
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 completed
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 input
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 error
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg.ps1 reset
```

Stop hook JSON check:

```powershell
$out = powershell -NoProfile -ExecutionPolicy Bypass -File .codex/hooks/set-terminal-bg-stop.ps1 completed
$out
$out | ConvertFrom-Json | Out-Null
```

## Limitations

- This is native Windows + VS Code.
- It uses OSC escape sequences; behavior depends on terminal support in the VS
  Code integrated terminal.
- The reliable lifecycle colors in this implementation are `idle`, `running`,
  `completed`, and `input`. Completion is handled by `Stop`, not
  `PostToolUse`, so the terminal stays blue while Codex is still working after
  a tool call.
- No local evidence was found for a reliable failure-only Codex hook such as
  `StopFailure` or a safely inspectable `PostToolUse` failure payload in this
  setup, so automatic red is not enabled in `hooks.json`.
- Red remains available as a manual/experimental state with:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.codex\hooks\set-terminal-bg.ps1 error`
- Stop hooks must not emit escape sequences on stdout. In this repo, the
  Windows-specific Stop script writes terminal OSC sequences to `CONOUT$` or
  stderr and returns exactly `{"continue":true}` on stdout.
- Current diagnosis: hook subprocesses need a native Windows `CreateFile`
  writer for `CONOUT$`; `[System.IO.File]::Open("CONOUT$")` is not reliable
  for this device. With `CreateFile`, Stop completion can set green while
  keeping stdout JSON-safe.
- If true selected/focused red is needed later, that should be built as a VS
  Code extension or external wrapper process, not mixed into this first
  implementation.

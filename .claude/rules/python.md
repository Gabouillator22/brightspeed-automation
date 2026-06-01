# Python Rules

These rules apply to all work in `05_toolkit/python/`.

## Determinism requirement
Scripts must be **purely deterministic** — same input always produces same output. No randomness, no AI inference, no fuzzy matching inside geometry code.

## Module structure
- One operation per module.
- Entry point via `argparse` with `main(argv=None)` pattern.
- `if __name__ == "__main__": sys.exit(main())` at bottom.

## Path handling
```python
# CORRECT
from pathlib import Path
input_file = Path(args.input_file)

# WRONG — never do this
input_file = "C:\\Users\\Gabriel\\..."
input_file = "/Users/gabriel/..."
```

## Allowed packages
`ezdxf`, `lxml`, `pyproj`, `shapely`, `json`, `pathlib`, `argparse`, `sys`, `math`

New dependencies require updating `04_documentation/BRIGHTSPEED_TOOLKIT_INSTALL.md`.

## Launchers
`.bat` files use `python "%~dp0script.py" %*` — no hardcoded Python path.

## Tests
- Required for every new module.
- Location: `05_toolkit/python/tests/<module>_test.py`.
- Framework: `pytest`.
- Must include at least: one happy path, one edge case (empty input or single vertex).

## Code style
- `ruff` for linting and formatting (configured to be non-breaking on .lsp adjacent Python).
- Type hints on function signatures.
- Docstring on every public function (one line is enough).

## Forbidden
- `os.system()` or `subprocess` for DWG operations.
- Hardcoded absolute paths.
- Mutable default arguments.
- `import *`.
- Writing binary `.dwg` — output to DXF or coordinate JSON only.

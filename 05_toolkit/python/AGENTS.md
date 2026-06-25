# Python Sub-brain — 05_toolkit/python/

## Principle
Deterministic geometry only. Scripts receive explicit coordinates and produce explicit output.
AI never places geometry — it only orchestrates and verifies.

## Module structure
One operation per module. Entry point via `argparse`.

```python
#!/usr/bin/env python3
"""One-line description of what this script does."""
import argparse, sys
from pathlib import Path

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input_file", type=Path)
    p.add_argument("output_file", type=Path)
    args = p.parse_args(argv)
    # ... deterministic logic ...
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

## Dependencies
```bash
python -m pip install ezdxf lxml pyproj shapely
```

## Launchers
`.bat` files call `python script.py` — no hardcoded Python path.
On Mac/Linux: `python3 script.py`.

## Tests
Location: `05_toolkit/python/tests/<module>_test.py`
Framework: `pytest`
Run: `pytest 05_toolkit/python/tests/ -v`

Every new module requires at least one test before merging.

## Mandatory status logging
- After any meaningful Python test, fix, regression, or validation result, update `04_documentation/TOOLKIT_STATUS.md` before ending the session.
- Log the exact script names touched, the status (`working`, `partial`, `broken`, `untested`, `regressed`), what was tested, known limitations, and the next action.

## File inventory
| File | Purpose |
|---|---|
| `bsbuild.py` | Build/package automation |
| `bsparcels.py` | Parcel geometry processing |
| `bssheetplan.py` | Sheet planning algorithm |
| `BUILD.bat` | Windows launcher for bsbuild.py |
| `bsparcels.bat` | Windows launcher for bsparcels.py |

## Path rules
- Always use `pathlib.Path` — never hardcode `/` or `\` separators.
- Never hardcode drive letters or user paths.
- Relative paths anchored to `Path(__file__).parent` or `argparse` input.

# /new-pyop

Create a new Python geometry operation module.

## Usage
```
/new-pyop <operation-name>
```

## What this does
1. Creates `05_toolkit/python/bs<operation-name>.py` with argparse entry point and deterministic geometry stub.
2. Creates `05_toolkit/python/bs<operation-name>.bat` Windows launcher.
3. Creates `05_toolkit/python/tests/bs<operation-name>_test.py` with a golden-file test stub.
4. Updates `05_toolkit/python/AGENTS.md` inventory table.

## Template (module)
```python
#!/usr/bin/env python3
"""[One-line description of what this operation does]."""
import argparse
import sys
from pathlib import Path


def process(input_path: Path, output_path: Path) -> int:
    """[Describe the transformation here.]"""
    # TODO: implement deterministic geometry logic
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input_file", type=Path, help="Input file path")
    p.add_argument("output_file", type=Path, help="Output file path")
    args = p.parse_args(argv)
    return process(args.input_file, args.output_file)


if __name__ == "__main__":
    sys.exit(main())
```

## Template (.bat launcher)
```bat
@echo off
python "%~dp0bs<operation-name>.py" %*
```

## Delegate to
`python-author` agent for implementation, `test-writer` agent for tests.

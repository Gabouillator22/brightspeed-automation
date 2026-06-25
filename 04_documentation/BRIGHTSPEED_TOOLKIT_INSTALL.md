# Brightspeed Toolkit Install

## What To Copy

Copy the whole `05_toolkit` folder to the other computer.

The most important folder is:

```text
05_toolkit\lisp
```

Do not copy only `bs_loader.lsp`. The loader depends on the other `.lsp` files in the same folder, and `BSKMZ` also depends on `bskmz.ps1` in that same folder.

## AutoCAD Setup

1. Open AutoCAD Map 3D.
2. Run `APPLOAD`.
3. Browse to the copied folder:

```text
05_toolkit\lisp\bs_loader.lsp
```

4. Load `bs_loader.lsp`.
5. Run:

```text
BSINSTALLCHECK
```

The command adds the toolkit folder to AutoCAD's support and trusted paths for that user profile, then reports any missing files.

## Python Tools

The `.bat` launchers in `05_toolkit\python` now use the target computer's installed Python instead of Gabriel's local Python path.

Install Python 3 and these packages before using Python-based tools:

```powershell
python -m pip install ezdxf lxml pyproj shapely
```

If `python` does not work, try:

```powershell
py -3 -m pip install ezdxf lxml pyproj shapely
```

## Common Failure Causes

- Only `bs_loader.lsp` was copied instead of the full `05_toolkit\lisp` folder.
- `bskmz.ps1` was not copied next to `bskmz.lsp`.
- AutoCAD blocked LISP loading because the copied folder was not trusted.
- A launcher pointed to `C:\Users\Gabriel\...Python312\python.exe` instead of Python on the other computer.
- Required Python packages were not installed on the other computer.

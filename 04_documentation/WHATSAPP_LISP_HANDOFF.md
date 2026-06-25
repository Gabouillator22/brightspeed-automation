# Brightspeed LISP Handoff

## What This Is

This folder contains the Brightspeed AutoCAD LISP tools.  
These files are meant to be loaded together, not one at a time.

## What To Do

1. Put the whole LISP folder in one place on your computer.
2. Open AutoCAD Map 3D.
3. Run `APPLOAD`.
4. Select `bs_loader.lsp`.
5. Load it.
6. Run `BSINSTALLCHECK`.

## What `BSINSTALLCHECK` Does

It checks that AutoCAD can see the full toolkit folder and that the required LISP files are present.

If it reports missing files, that usually means:

- only one `.lsp` file was copied instead of the full folder
- the folder was moved after loading
- AutoCAD is not pointed at the right folder yet

## How To Use It After That

After `bs_loader.lsp` loads successfully, the commands are available in AutoCAD.

Example commands:

- `BSROW`
- `BSPARCELS`
- `BSKMZ`
- `BSSHEETRECT`
- `BSSHEETLOAD`
- `BSSHEETMAKE`

## Important Note

For now, send the LISP files together as one folder.  
Later, if you use the KMZ import tools or Python-backed tools, those also need their companion files, but this guide is only for the LISP side.

## Short Message You Can Send On WhatsApp

```text
Put the whole LISP folder somewhere on your computer, open AutoCAD Map 3D, run APPLOAD, choose bs_loader.lsp, then run BSINSTALLCHECK. After that the Brightspeed commands should be available.
```

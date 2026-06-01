"""
bsbuild.py — one-shot starter-file builder

Reads a KMZ + basedata DWG, produces a single ready-to-open DXF
containing:
   * NC_Parcels (clipped to KMZ extent + 500' buffer)
        -> renamed to layer 'PROPERTY LINES'
   * KMZ buried fiber lines -> 'Buried Fiber in Duct'
   * KMZ aerial fiber lines -> 'AERIAL FIBER'
   * KMZ e-lash lines       -> 'E-LASH'

The DWG basedata is read via the AutoCAD-bundled accoreconsole.exe
(no extra installs needed). Resulting DXF is cached so the conversion
only happens when the source DWG changes.

Output: <kmz_stem>_ready.dxf next to the KMZ.
Optionally auto-opens the result in AutoCAD (see config).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from zipfile import ZipFile

import ezdxf
from ezdxf import bbox
from lxml import etree
from pyproj import Transformer

# Reuse the existing sheet-planning logic (shapely-based)
sys.path.insert(0, str(Path(__file__).parent))
import bssheetplan
from shapely.geometry import LineString


SAFETY_MARGIN_FT   = 500.0   # added to half-diagonal of the largest sheet
PARCELS_LAYER_SRC  = "NC_Parcels"
PARCELS_LAYER_DST  = "PROPERTY LINES"
SHEET_LAYER        = "BS-SHEET-PROPOSED"
SHEET_COLOR        = 30      # orange
KML_NS             = "{http://www.opengis.net/kml/2.2}"
TOOLKIT_DIR        = Path(__file__).resolve().parents[1]
CONFIG_DIR         = TOOLKIT_DIR / "config"
SHEET_CONFIG_FILE  = CONFIG_DIR / "bssheet_config.json"

# KMZ folder name -> output layer for LineString features
KMZ_LINE_LAYERS: dict[str, str] = {
    "UNDERGROUND": "Buried Fiber in Duct",
    "BURIED":      "Buried Fiber in Duct",
    "OVERLASH":    "E-LASH",
    "NEW STRAND/NEW BUILD": "AERIAL FIBER",
    "NEW STRAND":  "AERIAL FIBER",
    "NEW BUILD":   "AERIAL FIBER",
    "AERIAL":      "AERIAL FIBER",
    "ELASH":       "E-LASH",
    "E-LASH":      "E-LASH",
}

CONFIG_FILE = CONFIG_DIR / "bsbuild_config.json"


def log(msg: str) -> None:
    print(f"[bsbuild] {msg}")


# ---------- config ----------

def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text())
        except Exception:
            return {}
    return {}


def save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


def ask_file(title: str, filetypes: list[tuple[str, str]]) -> str:
    import tkinter as tk
    from tkinter import filedialog
    root = tk.Tk(); root.withdraw()
    p = filedialog.askopenfilename(title=title, filetypes=filetypes)
    root.destroy()
    return p


# ---------- discovery ----------

def find_accoreconsole() -> Path | None:
    for ver in ("2027", "2026", "2025", "2024"):
        p = Path(rf"C:\Program Files\Autodesk\AutoCAD {ver}\accoreconsole.exe")
        if p.exists():
            return p
        p = Path(rf"C:\Program Files\Autodesk\AutoCAD Map 3D {ver}\accoreconsole.exe")
        if p.exists():
            return p
    return None


def find_acad() -> Path | None:
    for ver in ("2027", "2026", "2025", "2024"):
        p = Path(rf"C:\Program Files\Autodesk\AutoCAD {ver}\acad.exe")
        if p.exists():
            return p
    return None


# ---------- basedata DWG -> DXF via accoreconsole ----------

def dxf_to_dwg(dxf_path: Path, dwg_path: Path) -> bool:
    """Convert a freshly-written DXF to DWG using accoreconsole. Returns True on success."""
    acc = find_accoreconsole()
    if acc is None:
        return False
    if dwg_path.exists():
        try: dwg_path.unlink()
        except: pass
    scr = dxf_path.with_suffix(".save.scr")
    # SAVEAS with empty version string -> default DWG format for installed AutoCAD
    scr.write_text(
        f'(command "_.FILEDIA" 0)\n'
        f'(command "_.SAVEAS" "" "{dwg_path.as_posix()}")\n'
        f'(command "_.FILEDIA" 1)\n'
        f'(command "_.QUIT" "_Y")\n'
    )
    try:
        subprocess.run(
            [str(acc), "/i", str(dxf_path), "/s", str(scr)],
            capture_output=True, text=True, timeout=180,
        )
    finally:
        if scr.exists():
            try: scr.unlink()
            except: pass
    return dwg_path.exists()


def dwg_to_dxf_cached(dwg_path: Path) -> Path:
    """Convert dwg -> dxf using accoreconsole. Cached: skips work if up-to-date."""
    dxf_path = dwg_path.with_suffix(".cached.dxf")
    if dxf_path.exists() and dxf_path.stat().st_mtime >= dwg_path.stat().st_mtime:
        log(f"  cached DXF up to date ({dxf_path.name})")
        return dxf_path

    acc = find_accoreconsole()
    if acc is None:
        raise RuntimeError(
            "accoreconsole.exe not found. Expected at "
            r"C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe"
        )

    log(f"  converting {dwg_path.name} -> DXF (first run, ~30 sec)...")
    # build the LISP-style script accoreconsole consumes line by line
    scr_path = dwg_path.parent / "_bsbuild_convert.scr"
    scr_path.write_text(
        f'(command "_.DXFOUT" "{dxf_path.as_posix()}" "V" "2018" "16")\n'
        f'(command "_.QUIT" "_Y")\n'
    )
    try:
        result = subprocess.run(
            [str(acc), "/i", str(dwg_path), "/s", str(scr_path)],
            capture_output=True, text=True, timeout=600
        )
        if not dxf_path.exists():
            log(f"  accoreconsole stdout: {result.stdout[-500:]}")
            log(f"  accoreconsole stderr: {result.stderr[-500:]}")
            raise RuntimeError("accoreconsole ran but did not produce DXF")
    finally:
        if scr_path.exists():
            try: scr_path.unlink()
            except: pass
    return dxf_path


# ---------- KMZ parsing ----------

def kmz_extract(kmz_path: Path) -> tuple[list[tuple[float, float]], list[tuple[str, list[tuple[float, float]]]]]:
    """Return (all_points_for_bbox, lines_by_folder).
    lines_by_folder is a list of (folder_name_upper, [(lon, lat), ...])."""
    with ZipFile(kmz_path) as z:
        kml_name = next(n for n in z.namelist() if n.lower().endswith(".kml"))
        with z.open(kml_name) as f:
            tree = etree.parse(f)

    all_pts: list[tuple[float, float]] = []
    lines: list[tuple[str, list[tuple[float, float]]]] = []

    # walk all <Document> elements and read their <name> + <Placemark>s
    for doc in tree.findall(f".//{KML_NS}Document"):
        name_el = doc.find(f"{KML_NS}name")
        folder = (name_el.text or "").strip().upper() if name_el is not None else ""
        for pm in doc.findall(f".//{KML_NS}Placemark"):
            # collect points
            for c in pm.findall(f".//{KML_NS}Point/{KML_NS}coordinates"):
                if c.text:
                    parts = c.text.strip().split(",")
                    if len(parts) >= 2:
                        try:
                            all_pts.append((float(parts[0]), float(parts[1])))
                        except ValueError:
                            pass
            # collect linestrings
            for c in pm.findall(f".//{KML_NS}LineString/{KML_NS}coordinates"):
                if not c.text:
                    continue
                pts: list[tuple[float, float]] = []
                for tok in c.text.split():
                    parts = tok.split(",")
                    if len(parts) >= 2:
                        try:
                            pts.append((float(parts[0]), float(parts[1])))
                        except ValueError:
                            pass
                if len(pts) >= 2:
                    all_pts.extend(pts)
                    lines.append((folder, pts))

    if not all_pts:
        raise RuntimeError("No coordinates found in KMZ")
    return all_pts, lines


# ---------- coord conversion ----------

_TX = Transformer.from_crs("EPSG:4326", "EPSG:2264", always_xy=True)
def ll_to_ft(lon: float, lat: float) -> tuple[float, float]:
    return _TX.transform(lon, lat)


# ---------- bbox math ----------

def compute_buffer_ft(sheet_cfg: dict) -> float:
    """Buffer = half-diagonal of the sheet + safety. Auto-adapts when
    sheet_width_ft / sheet_height_ft change in bssheet_config.json."""
    w = float(sheet_cfg.get("sheet_width_ft", 974))
    h = float(sheet_cfg.get("sheet_height_ft", 473))
    return ((w * w + h * h) ** 0.5) / 2.0 + SAFETY_MARGIN_FT


def latlon_bbox_to_ncsp(pts: list[tuple[float, float]], buffer_ft: float) -> tuple[float, float, float, float]:
    lons = [p[0] for p in pts]; lats = [p[1] for p in pts]
    lon_min, lon_max = min(lons), max(lons)
    lat_min, lat_max = min(lats), max(lats)
    corners = [ll_to_ft(lon_min, lat_min), ll_to_ft(lon_max, lat_min),
               ll_to_ft(lon_max, lat_max), ll_to_ft(lon_min, lat_max)]
    xs = [c[0] for c in corners]; ys = [c[1] for c in corners]
    return (min(xs) - buffer_ft, min(ys) - buffer_ft,
            max(xs) + buffer_ft, max(ys) + buffer_ft)


def entity_bbox(ent):
    try:
        b = bbox.extents([ent], fast=True)
    except Exception:
        return None
    if b is None or not b.has_data:
        return None
    return (b.extmin.x, b.extmin.y, b.extmax.x, b.extmax.y)


def boxes_intersect(a, b) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


# ---------- parcel copy ----------

def extract_mpolygon_rings(ent) -> list[list[tuple[float, float]]]:
    rings: list[list[tuple[float, float]]] = []
    try:
        paths = ent.paths
    except Exception:
        return rings
    polyline_paths = getattr(paths, "polyline_paths", None)
    iterable = polyline_paths if polyline_paths is not None else paths
    try:
        for path in iterable:
            verts_attr = getattr(path, "vertices", None)
            if verts_attr is None:
                continue
            verts = [(float(v[0]), float(v[1])) for v in verts_attr]
            if len(verts) >= 2:
                rings.append(verts)
    except Exception:
        pass
    return rings


def copy_parcel(ent, msp_out, layer: str) -> int:
    attribs = {"layer": layer}
    written = 0
    t = ent.dxftype()
    try:
        if t == "MPOLYGON":
            for ring in extract_mpolygon_rings(ent):
                msp_out.add_lwpolyline(ring, close=True, dxfattribs=attribs)
                written += 1
        elif t == "LWPOLYLINE":
            v = [(p[0], p[1]) for p in ent.get_points("xy")]
            if len(v) >= 2:
                msp_out.add_lwpolyline(v, close=bool(ent.closed), dxfattribs=attribs); written += 1
        elif t == "POLYLINE":
            v = [(float(x.dxf.location.x), float(x.dxf.location.y)) for x in ent.vertices]
            if len(v) >= 2:
                msp_out.add_lwpolyline(v, close=bool(ent.is_closed), dxfattribs=attribs); written += 1
        elif t == "LINE":
            s = ent.dxf.start; e = ent.dxf.end
            msp_out.add_line((s.x, s.y), (e.x, e.y), dxfattribs=attribs); written += 1
        elif t == "HATCH":
            try:
                for path in ent.paths.polyline_paths:
                    v = [(p[0], p[1]) for p in path.vertices]
                    if len(v) >= 2:
                        msp_out.add_lwpolyline(v, close=True, dxfattribs=attribs); written += 1
            except Exception:
                pass
    except Exception as e:
        log(f"  WARN: failed to copy {t}: {e}")
    return written


# ---------- main pipeline ----------

def get_basedata() -> Path | None:
    log("STEP 1 of 2 — pick the basedata DWG (the one with NC_Parcels)...")
    chosen = ask_file("STEP 1 of 2 — Select basedata DWG",
                      [("DWG/DXF", "*.dwg *.dxf")])
    return Path(chosen) if chosen else None


def get_kmz() -> Path | None:
    log("STEP 2 of 2 — pick the KMZ for this project...")
    chosen = ask_file("STEP 2 of 2 — Select KMZ",
                      [("KMZ", "*.kmz")])
    return Path(chosen) if chosen else None


def get_template() -> Path | None:
    """Auto-detect template from AUTOMATION folder. Falls back to picker."""
    here = Path(__file__).parent
    for pat in ("BSP NCDOT TEMPLATE*.dwg", "BSP NCDOT TEMPLATE*.dxf",
                "*TEMPLATE*.dwg", "*TEMPLATE*.dxf"):
        hits = sorted(here.glob(pat))
        if hits:
            log(f"Template (auto-detected in AUTOMATION folder): {hits[-1].name}")
            return hits[-1]
    log("Template not auto-found — pick it...")
    chosen = ask_file("Select template DWG", [("DWG/DXF", "*.dwg *.dxf")])
    return Path(chosen) if chosen else None


def derive_job_name(kmz: Path) -> str:
    stem = kmz.stem
    # strip common trailing suffixes so the folder name is clean
    for suffix in ("_PERMITS", "_permits", "-PERMITS", "_permit", "_PERMIT"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break
    return stem


def main() -> int:
    log("Brightspeed starter-file builder")

    basedata = get_basedata()
    if not basedata:
        log("No basedata — exit.")
        return 1
    log(f"Basedata: {basedata}")

    kmz = get_kmz()
    if not kmz:
        log("No KMZ — exit.")
        return 1
    log(f"KMZ:      {kmz}")

    template = get_template()
    if not template:
        log("No template — exit.")
        return 1

    # 1) ensure basedata and template are DXF (convert via accoreconsole if needed)
    log("Preparing basedata...")
    basedata_dxf = dwg_to_dxf_cached(basedata) if basedata.suffix.lower() == ".dwg" else basedata
    log("Preparing template...")
    template_dxf = dwg_to_dxf_cached(template) if template.suffix.lower() == ".dwg" else template

    # 2) load sheet config + compute parcel buffer from sheet diagonal
    sheet_cfg = bssheetplan.load_config(SHEET_CONFIG_FILE)
    buffer_ft = compute_buffer_ft(sheet_cfg)
    log(f"Sheet size:  {sheet_cfg['sheet_width_ft']} x {sheet_cfg['sheet_height_ft']} ft")
    log(f"Parcel buffer (auto): {buffer_ft:.0f} ft  "
        f"(sheet half-diagonal + {SAFETY_MARGIN_FT:.0f}' safety)")

    # 3) read KMZ
    log("Reading KMZ...")
    all_pts_ll, lines_by_folder = kmz_extract(kmz)
    bx = latlon_bbox_to_ncsp(all_pts_ll, buffer_ft)
    log(f"  NCSP bbox: X[{bx[0]:.0f}..{bx[2]:.0f}] Y[{bx[1]:.0f}..{bx[3]:.0f}]")

    # 3) open basedata DXF, filter parcels
    log("Filtering parcels...")
    doc_src = ezdxf.readfile(str(basedata_dxf))
    msp_src = doc_src.modelspace()

    type_counts: dict[str, int] = {}
    total = 0; kept = []
    for ent in msp_src.query(f'*[layer=="{PARCELS_LAYER_SRC}"]'):
        total += 1
        type_counts[ent.dxftype()] = type_counts.get(ent.dxftype(), 0) + 1
        eb = entity_bbox(ent)
        if eb and boxes_intersect(eb, bx):
            kept.append(ent)
    log(f"  parcels on layer: {total}  types: {type_counts}")
    log(f"  inside KMZ area:  {len(kept)}")

    if total == 0:
        log(f"  WARN: no entities on '{PARCELS_LAYER_SRC}' — is the layer name right?")

    # 4) prepare output folder
    job_name = derive_job_name(kmz)
    job_dir = kmz.parent / job_name
    job_dir.mkdir(exist_ok=True)
    working_path = job_dir / f"{job_name}_WORKING.dxf"
    dataset_path = job_dir / f"{job_name}_DATASET.dxf"
    log(f"Job folder: {job_dir}")

    # 5) open template as the WORKING doc; ensure required layers exist (without overriding existing)
    log(f"Opening template: {template.name}")
    doc_out = ezdxf.readfile(str(template_dxf))
    if PARCELS_LAYER_DST not in doc_out.layers:
        doc_out.layers.add(PARCELS_LAYER_DST, color=7)
    for layer in set(KMZ_LINE_LAYERS.values()):
        if layer not in doc_out.layers:
            color = 1 if "AERIAL" in layer else 5 if "Buried" in layer else 6
            doc_out.layers.add(layer, color=color)
    if SHEET_LAYER not in doc_out.layers:
        doc_out.layers.add(SHEET_LAYER, color=SHEET_COLOR)

    msp_out = doc_out.modelspace()

    # 5a) parcels into the WORKING file
    n_parcels = 0
    for ent in kept:
        n_parcels += copy_parcel(ent, msp_out, PARCELS_LAYER_DST)

    # 5b) KMZ fiber lines into the WORKING file (and keep route geometry for sheet planning)
    n_lines = 0; skipped_folders: set[str] = set()
    route_parts_ft: list[bssheetplan.RoutePart] = []
    for folder, latlon_pts in lines_by_folder:
        ft_pts = [ll_to_ft(lon, lat) for lon, lat in latlon_pts]
        # decide layer
        layer = None
        for key, lyr in KMZ_LINE_LAYERS.items():
            if key in folder:
                layer = lyr; break
        if layer is None:
            skipped_folders.add(folder)
        else:
            msp_out.add_lwpolyline(ft_pts, dxfattribs={"layer": layer})
            n_lines += 1
        # always feed into sheet planner (sheets follow the field route, mapped or not)
        route_parts_ft.append(bssheetplan.RoutePart(name=folder or "route", coords=ft_pts))

    # 5c) plan proposed sheets along the route and draw them on BS-SHEET-PROPOSED
    n_sheets = 0
    sheet_warnings: list[str] = []
    if route_parts_ft:
        log("Planning proposed sheets...")
        merged = bssheetplan.merge_touching_parts(route_parts_ft)
        start = 1
        for branch_index, (_name, line) in enumerate(merged, start=1):
            sheets, warns = bssheetplan.plan_line(branch_index, line, sheet_cfg, start)
            sheet_warnings.extend(warns)
            for s in sheets:
                # closed rectangle on proposed-sheet layer (orange)
                msp_out.add_lwpolyline(
                    s.vertices, close=True,
                    dxfattribs={"layer": SHEET_LAYER}
                )
                n_sheets += 1
            start += len(sheets)
        log(f"  Sheets placed: {n_sheets}")
        if sheet_warnings:
            for w in sheet_warnings[:5]:
                log(f"  sheet WARN: {w}")
            if len(sheet_warnings) > 5:
                log(f"  ({len(sheet_warnings) - 5} more warnings suppressed)")

    doc_out.saveas(str(working_path))
    log(f"  WORKING: {n_parcels} parcels + {n_lines} fiber lines + {n_sheets} sheets into template")

    # 6) also write the parcels-only DATASET file (lightweight reference)
    log("Writing dataset (parcels-only) file...")
    doc_ds = ezdxf.new("R2018", setup=True)
    if PARCELS_LAYER_DST not in doc_ds.layers:
        doc_ds.layers.add(PARCELS_LAYER_DST, color=7)
    msp_ds = doc_ds.modelspace()
    for ent in kept:
        copy_parcel(ent, msp_ds, PARCELS_LAYER_DST)
    doc_ds.saveas(str(dataset_path))
    log(f"  DATASET: parcels-only reference written")

    # 7) convert both to DWG so they double-click open in AutoCAD
    log("Converting outputs to DWG...")
    working_dwg = working_path.with_suffix(".dwg")
    dataset_dwg = dataset_path.with_suffix(".dwg")
    ok_w = dxf_to_dwg(working_path, working_dwg)
    ok_d = dxf_to_dwg(dataset_path, dataset_dwg)
    if ok_w:
        try: working_path.unlink()
        except: pass
    if ok_d:
        try: dataset_path.unlink()
        except: pass

    if skipped_folders:
        log(f"  (KMZ folders skipped — no matching layer: {sorted(skipped_folders)})")
    log("")
    log(f"DONE. Job folder: {job_dir}")
    if ok_w:
        log(f"  -> {working_dwg.name}  (double-click to open in AutoCAD)")
    else:
        log(f"  -> {working_path.name}  (DWG conversion failed — open as DXF)")
    if ok_d:
        log(f"  -> {dataset_dwg.name}  (parcels-only reference)")
    else:
        log(f"  -> {dataset_path.name}  (parcels-only reference, DXF)")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except KeyboardInterrupt:
        log("Interrupted."); rc = 1
    except Exception as e:
        log(f"FATAL: {e}")
        import traceback; traceback.print_exc()
        rc = 1
    if os.environ.get("BSBUILD_PAUSE", "1") == "1":
        input("\nPress Enter to close...")
    sys.exit(rc)

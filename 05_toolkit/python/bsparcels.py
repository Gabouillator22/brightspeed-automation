"""
bsparcels.py — Brightspeed parcel extractor

Reads a KMZ field file, computes its NC State Plane bounding box + 500'
buffer, opens a basedata DXF/DWG containing the county NC_Parcels, and
writes out a new DXF containing only the parcels in the buffered area —
relabeled onto the PROPERTY LINES layer ready to be inserted into a
working drawing at (0,0,0).

Usage (typical, via launcher):
    bsparcels.bat path\\to\\job.kmz

First run will prompt for the basedata file location and remember it.
"""

from __future__ import annotations

import json
import sys
import os
from pathlib import Path
from zipfile import ZipFile

import ezdxf
from ezdxf import bbox
from lxml import etree
from pyproj import Transformer


# ---------- tuning ----------
BUFFER_FT          = 500.0
PARCELS_LAYER_SRC  = "NC_Parcels"
PARCELS_LAYER_DST  = "PROPERTY LINES"
KML_NS             = "{http://www.opengis.net/kml/2.2}"

TOOLKIT_DIR = Path(__file__).resolve().parents[1]
CONFIG_DIR = TOOLKIT_DIR / "config"
CONFIG_FILE = CONFIG_DIR / "bsparcels_config.json"


# ---------- helpers ----------

def log(msg: str) -> None:
    print(f"[bsparcels] {msg}")


def kmz_bbox_latlon(kmz_path: Path) -> tuple[float, float, float, float]:
    """Return (lon_min, lat_min, lon_max, lat_max) for all coords in the KMZ."""
    with ZipFile(kmz_path) as z:
        kml_name = next(n for n in z.namelist() if n.lower().endswith(".kml"))
        with z.open(kml_name) as f:
            tree = etree.parse(f)
    coords_elems = tree.findall(f".//{KML_NS}coordinates")
    lons: list[float] = []
    lats: list[float] = []
    for el in coords_elems:
        if not el.text:
            continue
        for token in el.text.split():
            parts = token.split(",")
            if len(parts) >= 2:
                try:
                    lons.append(float(parts[0]))
                    lats.append(float(parts[1]))
                except ValueError:
                    pass
    if not lons:
        raise RuntimeError("No coordinates found in KMZ")
    return (min(lons), min(lats), max(lons), max(lats))


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

    root = tk.Tk()
    root.withdraw()
    path = filedialog.askopenfilename(title=title, filetypes=filetypes)
    root.destroy()
    return path


def get_kmz_arg() -> Path | None:
    if len(sys.argv) >= 2 and sys.argv[1].lower().endswith(".kmz"):
        p = Path(sys.argv[1])
        if p.exists():
            return p
    log("No KMZ passed on command line — opening file picker.")
    chosen = ask_file("Select KMZ", [("KMZ files", "*.kmz")])
    return Path(chosen) if chosen else None


def get_dataset_path(cfg: dict) -> Path | None:
    cached = cfg.get("dataset")
    if cached and Path(cached).exists():
        log(f"Using cached basedata: {cached}")
        log("   (delete bsparcels_config.json to pick a different one)")
        return Path(cached)
    log("Basedata file not configured — opening file picker.")
    chosen = ask_file(
        "Select basedata file (DXF preferred, DWG requires ODA File Converter)",
        [("DXF/DWG", "*.dxf *.dwg"), ("DXF", "*.dxf"), ("DWG", "*.dwg")],
    )
    if not chosen:
        return None
    cfg["dataset"] = chosen
    save_config(cfg)
    return Path(chosen)


def read_dataset(path: Path):
    """Open the basedata. Prefers DXF (native). DWG falls through to ODA addon."""
    suffix = path.suffix.lower()
    if suffix == ".dxf":
        return ezdxf.readfile(str(path))
    if suffix == ".dwg":
        try:
            from ezdxf.addons import odafc
        except Exception as e:
            raise RuntimeError(
                "Reading DWG requires the ODA File Converter. Easiest fix: "
                "open the basedata in AutoCAD, File > Save As > AutoCAD DXF, "
                "then re-run bsparcels and pick the .dxf."
            ) from e
        return odafc.readfile(str(path))
    raise RuntimeError(f"Unsupported file type: {suffix}")


def entity_bbox(ent):
    """ezdxf bbox wrapper — returns (xmin, ymin, xmax, ymax) or None."""
    try:
        b = bbox.extents([ent], fast=True)
    except Exception:
        return None
    if b is None or not b.has_data:
        return None
    return (b.extmin.x, b.extmin.y, b.extmax.x, b.extmax.y)


def boxes_intersect(a, b) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def extract_polylines_from_mpolygon(ent) -> list[list[tuple[float, float]]]:
    """Pull boundary vertex rings out of an MPOLYGON entity.
    Returns a list of vertex lists (one per ring)."""
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


def copy_entity_to(ent, msp_out, layer_name: str) -> int:
    """Copy one source entity to msp_out on the target layer. Returns count written."""
    written = 0
    dxftype = ent.dxftype()
    attribs = {"layer": layer_name}

    try:
        if dxftype == "MPOLYGON":
            for ring in extract_polylines_from_mpolygon(ent):
                msp_out.add_lwpolyline(ring, close=True, dxfattribs=attribs)
                written += 1

        elif dxftype == "LWPOLYLINE":
            verts = [(p[0], p[1]) for p in ent.get_points("xy")]
            if len(verts) >= 2:
                msp_out.add_lwpolyline(verts, close=bool(ent.closed), dxfattribs=attribs)
                written += 1

        elif dxftype == "POLYLINE":
            verts = []
            for v in ent.vertices:
                loc = v.dxf.location
                verts.append((float(loc.x), float(loc.y)))
            if len(verts) >= 2:
                msp_out.add_lwpolyline(verts, close=bool(ent.is_closed), dxfattribs=attribs)
                written += 1

        elif dxftype == "LINE":
            s = ent.dxf.start
            e = ent.dxf.end
            msp_out.add_line((s.x, s.y), (e.x, e.y), dxfattribs=attribs)
            written += 1

        elif dxftype == "HATCH":
            # treat like MPolygon — extract polyline boundary paths
            try:
                for path in ent.paths.polyline_paths:
                    verts = [(v[0], v[1]) for v in path.vertices]
                    if len(verts) >= 2:
                        msp_out.add_lwpolyline(verts, close=True, dxfattribs=attribs)
                        written += 1
            except Exception:
                pass
        # silently skip unsupported types
    except Exception as e:
        log(f"WARN: failed to copy {dxftype}: {e}")

    return written


# ---------- main ----------

def main() -> int:
    log("Brightspeed parcel extractor")

    kmz = get_kmz_arg()
    if not kmz:
        log("Cancelled — no KMZ.")
        return 1
    log(f"KMZ: {kmz}")

    cfg = load_config()
    dataset = get_dataset_path(cfg)
    if not dataset:
        log("Cancelled — no basedata file.")
        return 1

    # 1. KMZ extent
    log("Reading KMZ extent...")
    lon_min, lat_min, lon_max, lat_max = kmz_bbox_latlon(kmz)
    log(f"  lon/lat: ({lon_min:.5f}, {lat_min:.5f}) -> ({lon_max:.5f}, {lat_max:.5f})")

    # 2. project all 4 corners to NC State Plane
    tx = Transformer.from_crs("EPSG:4326", "EPSG:2264", always_xy=True)
    corners = [
        tx.transform(lon_min, lat_min),
        tx.transform(lon_max, lat_min),
        tx.transform(lon_max, lat_max),
        tx.transform(lon_min, lat_max),
    ]
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    x_min, x_max = min(xs) - BUFFER_FT, max(xs) + BUFFER_FT
    y_min, y_max = min(ys) - BUFFER_FT, max(ys) + BUFFER_FT
    query_box = (x_min, y_min, x_max, y_max)
    log(f"  NCSP buffered: X[{x_min:.1f}..{x_max:.1f}] Y[{y_min:.1f}..{y_max:.1f}]")
    log(f"  (KMZ extent + {BUFFER_FT:.0f}' buffer on every side)")

    # 3. open basedata
    log(f"Opening basedata: {dataset.name}")
    try:
        doc_src = read_dataset(dataset)
    except Exception as e:
        log(f"ERROR: {e}")
        return 1
    msp_src = doc_src.modelspace()

    # 4. iterate parcels layer
    log(f"Scanning entities on layer '{PARCELS_LAYER_SRC}'...")
    total = 0
    kept: list = []
    type_counts: dict[str, int] = {}
    for ent in msp_src.query(f'*[layer=="{PARCELS_LAYER_SRC}"]'):
        total += 1
        type_counts[ent.dxftype()] = type_counts.get(ent.dxftype(), 0) + 1
        eb = entity_bbox(ent)
        if eb is None:
            continue
        if boxes_intersect(eb, query_box):
            kept.append(ent)
    log(f"  total on layer: {total}")
    log(f"  entity mix:     {type_counts}")
    log(f"  inside buffer:  {len(kept)}")

    if total == 0:
        log("WARN: zero entities on that layer. Double-check the layer name in")
        log(f"      the basedata DWG matches exactly: '{PARCELS_LAYER_SRC}'")
        return 1
    if not kept:
        log("Nothing in the buffered area — basedata may not cover this region.")
        return 1

    # 5. build output
    out_path = kmz.parent / f"parcels_{kmz.stem}.dxf"
    log(f"Writing {out_path.name}...")
    doc_out = ezdxf.new("R2018", setup=True)
    if PARCELS_LAYER_DST not in doc_out.layers:
        doc_out.layers.add(PARCELS_LAYER_DST, color=7)

    msp_out = doc_out.modelspace()
    written = 0
    skipped = 0
    for ent in kept:
        n = copy_entity_to(ent, msp_out, PARCELS_LAYER_DST)
        if n == 0:
            skipped += 1
        written += n

    doc_out.saveas(str(out_path))
    log(f"DONE: wrote {written} polylines on '{PARCELS_LAYER_DST}' layer")
    if skipped:
        log(f"   ({skipped} source entities could not be converted — usually proxy types)")
    log("")
    log("Next steps:")
    log(f"  1. Open your working drawing in AutoCAD")
    log(f"  2. INSERT (or drag) {out_path.name} at 0,0,0 with scale 1")
    log(f"  3. Explode the insert if you want individual editable lines")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except KeyboardInterrupt:
        log("Interrupted.")
        rc = 1
    except Exception as e:
        log(f"FATAL: {e}")
        import traceback
        traceback.print_exc()
        rc = 1
    # Keep window open when launched by .bat (double-click case)
    if os.environ.get("BSPARCELS_PAUSE", "1") == "1":
        input("\nPress Enter to close...")
    sys.exit(rc)

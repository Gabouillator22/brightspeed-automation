# Manifest Schema — Skill Reference

A **manifest** is a JSON document that describes one permit job: what files exist, what was produced, and any findings from automated checks.

## Producer manifest shape

```json
{
  "job_id": "FRMTNCXA-VANCE-V5",
  "permit_set": "FRMTNCXA_VANCE_V5",
  "created_at": "2026-06-01T14:00:00Z",
  "machine": "windows-autocad",
  "input": {
    "kmz_path": "<relative-to-job-root>",
    "dwg_template": "BSP NCDOT TEMPLATE 04-07-2026.dwg",
    "base_drawing": "<path>"
  },
  "outputs": [
    {
      "type": "permit_sheet",
      "sheet_number": 1,
      "dwg_path": "<relative>",
      "page_title": "FRMTNCXA VANCE SHEET 1 OF 25"
    }
  ],
  "layers_present": ["ROW", "Buried Fiber in Duct", "AERIAL FIBER", "BORDER"],
  "sheet_count": 25,
  "findings": []
}
```

## Findings contract

Each finding is typed as one of three severity levels:

```json
{
  "id": "F001",
  "severity": "FIX",
  "check": "label-format",
  "entity_handle": "2A4F",
  "layer": "STATIONING",
  "current_value": "STA 12+54 HH#01",
  "expected_value": "STA 12+54 PL HANDHOLE",
  "auto_fixable": true,
  "notes": "Legacy label format — update to spec"
}
```

### Severity levels
| Level | Meaning | Action |
|---|---|---|
| `PASS` | Check passed | None |
| `FIX` | Auto-correctable deviation | Apply fix automatically |
| `ESCALATE` | Requires human judgment | Stop, report to operator |

### Defined checks
| Check ID | Description | Severity if failed |
|---|---|---|
| `sheet-count` | Permit has ≤ 25 sheets | ESCALATE |
| `label-format-hh` | Handhole label matches `STA XX+XX PL HANDHOLE` | FIX |
| `label-format-bore` | Bore pit label matches `STA XX+XX PL 36"X36" BORE PIT` | FIX |
| `label-format-callout` | Buried callout starts with `HDD BORE` | FIX |
| `aerial-no-footage` | Aerial callout has no footage number | FIX |
| `text-height` | All labels at 5.0 (street names 6.0) | FIX |
| `fiber-width` | Fiber polylines have global width 0.5 | FIX |
| `linetype-gen` | Fiber polylines have PLINEGEN enabled | FIX |
| `layer-color` | No manually assigned colors (group 62 in entmake) | FIX |
| `hardcoded-path` | No absolute paths in .lsp files | ESCALATE |
| `border-layer` | Sheet number blocks are on BORDER layer | FIX |
| `min-doc` | MIN DOC 60" note present on underground sheets | FIX |
| `work-area-label` | WORK AREA labels match format spec | FIX |
| `dwg-location` | DWG not on Mac shared path | ESCALATE |

## Manifest file location
`06_jobs/<job_id>/manifest.json`

## Consumption
- `BSAUDIT` reads the drawing and writes findings to `manifest.json`.
- Python scripts in `05_toolkit/python/` may append findings.
- `code-reviewer` agent reads `manifest.json` findings before approving a commit.

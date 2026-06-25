from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import bspackage


def test_parse_sheet_number_accepts_plain_number() -> None:
    assert bspackage.parse_sheet_number("14") == 14


def test_parse_sheet_number_accepts_prefixed_number() -> None:
    assert bspackage.parse_sheet_number("S014") == 14


def test_parse_sheet_number_accepts_sheet_label() -> None:
    assert bspackage.parse_sheet_number("SHEET #14") == 14


def test_parse_sheet_number_rejects_of_label() -> None:
    assert bspackage.parse_sheet_number("2 OF 8") is None


def test_parse_sheet_number_rejects_fraction_label() -> None:
    assert bspackage.parse_sheet_number("14/25") is None


def test_point_in_rectangle_matches_horizontal_sheet() -> None:
    rectangle = bspackage.Rectangle("AA", "BORDER", 0.0, 0.0, 100.0, 50.0)
    assert bspackage.point_in_rectangle(50.0, 25.0, rectangle)
    assert not bspackage.point_in_rectangle(150.0, 25.0, rectangle)


def test_duplicate_number_detection_fails_index() -> None:
    rectangles = [
        bspackage.Rectangle("R1", "BORDER", 0.0, 0.0, 100.0, 50.0),
        bspackage.Rectangle("R2", "BORDER", 150.0, 0.0, 250.0, 50.0),
    ]
    numbers = [
        bspackage.NumberCandidate("N1", "TEXT", "1", 1, 25.0, 25.0),
        bspackage.NumberCandidate("N2", "TEXT", "1", 1, 175.0, 25.0),
    ]
    _sheets, errors = bspackage.match_numbers_to_rectangles(rectangles, numbers)
    assert any("Duplicate sheet number 1" in error for error in errors)


def test_rectangle_without_number_detection_fails_index() -> None:
    rectangles = [
        bspackage.Rectangle("R1", "BORDER", 0.0, 0.0, 100.0, 50.0),
        bspackage.Rectangle("R2", "BORDER", 150.0, 0.0, 250.0, 50.0),
    ]
    numbers = [bspackage.NumberCandidate("N1", "TEXT", "1", 1, 25.0, 25.0)]
    _sheets, errors = bspackage.match_numbers_to_rectangles(rectangles, numbers)
    assert any("Rectangle R2 has no manual BORDER number." == error for error in errors)


def test_number_outside_every_rectangle_detection_fails_index() -> None:
    rectangles = [bspackage.Rectangle("R1", "BORDER", 0.0, 0.0, 100.0, 50.0)]
    numbers = [bspackage.NumberCandidate("N1", "TEXT", "1", 1, 250.0, 25.0)]
    _sheets, errors = bspackage.match_numbers_to_rectangles(rectangles, numbers)
    assert any("outside every sheet rectangle" in error for error in errors)


def test_existing_layouts_one_to_nine_require_ten_to_forty_five() -> None:
    existing = [str(value) for value in range(1, 10)]
    required = list(range(1, 46))
    missing = bspackage.missing_layout_names(existing, required)
    assert missing == [str(value) for value in range(10, 46)]


def test_layout_fourteen_maps_to_sheet_fourteen() -> None:
    plan = bspackage.layout_plan([str(value) for value in range(1, 10)], list(range(1, 46)), "2")
    entry = next(item for item in plan if item["sheet_number"] == 14)
    assert entry["layout_name"] == "14"
    assert entry["action"] == "copy_template"


def test_titleblock_values_without_sectioning_use_sheet_total() -> None:
    values = bspackage.titleblock_page_values(14, 45, bspackage.DEFAULT_CONFIG.copy())
    assert values["sheet_value"] == 14
    assert values["total_value"] == 45


def test_titleblock_values_with_sectioning_use_page_slot_counts() -> None:
    config = bspackage.DEFAULT_CONFIG.copy()
    config.update(
        {
            "sectioning_enabled": True,
            "max_pages_per_permit": 25,
            "first_plan_page_in_section": 2,
            "plan_slots_per_full_section": 24,
        }
    )
    values = bspackage.titleblock_page_values(45, 45, config)
    assert values["section_number"] == 2
    assert values["sheet_value"] == 22
    assert values["total_value"] == 22


def test_output_path_generation_avoids_overwrite() -> None:
    source = Path("C:/jobs/test.dwg")
    occupied = {Path("C:/jobs/test_PACKAGED.dwg")}
    output = bspackage.choose_output_dwg_path(
        source,
        "_PACKAGED",
        existing_paths=occupied,
        timestamp="20260608_120000",
    )
    assert output == Path("C:/jobs/test_PACKAGED_20260608_120000.dwg")


def test_write_index_outputs_creates_json_csv_and_markdown(tmp_path: Path) -> None:
    payload = {
        "source_dwg": "C:/jobs/test.dwg",
        "plan_template_layout": "2",
        "errors": [],
        "warnings": [],
        "sheets": [
            {
                "sheet_number": 14,
                "rectangle_handle": "AA",
                "rectangle_layer": "BORDER",
                "number_handle": "BB",
                "number_entity_type": "TEXT",
                "number_text": "14",
                "confidence": "HIGH",
                "bbox": {"min_x": 0.0, "min_y": 0.0, "max_x": 100.0, "max_y": 50.0},
                "center": {"x": 50.0, "y": 25.0},
                "width": 100.0,
                "height": 50.0,
            }
        ],
    }
    bspackage.write_index_outputs(payload, tmp_path)
    assert (tmp_path / "sheet_index.json").exists()
    assert (tmp_path / "sheet_index.csv").exists()
    assert (tmp_path / "sheet_index_report.md").exists()

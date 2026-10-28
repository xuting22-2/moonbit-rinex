#!/usr/bin/env python3
"""Independent, standard-library RINEX 4.01 OBS reference audit for the BRUX sample.

Research oracle only, not a production parser. It preserves the source time
system, applies the spec-defined 16-character observation slots, and records
where variable record lengths are right-padded to header-declared arity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

SPEC_URL = "https://files.igs.org/pub/data/format/rinex_4.01.pdf"
DEFAULT_INPUT = "BRUX00BEL_R_20262660000_01D_30S_MO.rnx"
SAT_ID = re.compile(r"^([A-Z])(\d{2})")
VALUE_F14_3 = re.compile(r"^[+-]?(?:\d+)?\.\d{3}$")
OBS_SLOT_WIDTH = 16
OBS_VALUE_WIDTH = 14
LLI_VALUES = set("01234567")
SSI_VALUES = set("0123456789")
KNOWN_LABELS = {
    "RINEX VERSION / TYPE", "PGM / RUN BY / DATE", "COMMENT",
    "MARKER NAME", "MARKER NUMBER", "MARKER TYPE", "OBSERVER / AGENCY",
    "DOI", "LICENSE OF USE", "STATION INFORMATION", "REC # / TYPE / VERS",
    "ANT # / TYPE", "APPROX POSITION XYZ", "ANTENNA: DELTA H/E/N",
    "SYS / # / OBS TYPES", "INTERVAL", "TIME OF FIRST OBS",
    "TIME OF LAST OBS", "# OF SATELLITES", "SIGNAL STRENGTH UNIT",
    "LEAP SECONDS", "GLONASS SLOT / FRQ #", "PRN / # OF OBS",
    "RCV CLOCK OFFS APPL", "END OF HEADER", "SYS / DCBS APPLIED",
    "SYS / PCVS APPLIED", "SYS / SCALE FACTOR", "SYS / PHASE SHIFT",
    "GLONASS COD/PHS/BIS",
}
EPOCH_FLAG_SEMANTICS = {
    0: "normal observation epoch",
    1: "power failure between previous and current epoch",
    2: "start moving antenna event",
    3: "new site occupation / end of kinematic data",
    4: "header information follows",
    5: "external event",
    6: "cycle-slip records follow",
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def label_of(line: str) -> str:
    return line[60:80].strip() if len(line) >= 60 else ""


def text_before_label(line: str) -> str:
    return line[:60] if len(line) >= 60 else line


def parse_stamp_tokens(tokens: list[str]) -> tuple[str | None, Decimal | None]:
    if len(tokens) < 6:
        return None, None
    try:
        y, mo, d, hh, mm = (int(x) for x in tokens[:5])
        sec = Decimal(tokens[5])
        if not (1 <= mo <= 12 and 1 <= d <= 31 and 0 <= hh <= 23 and 0 <= mm <= 59):
            return None, None
        ordinal = date(y, mo, d).toordinal()
        scalar = Decimal(ordinal * 86400 + hh * 3600 + mm * 60) + sec
        sec_int = int(sec)
        fraction = format(sec - Decimal(sec_int), "f")
        frac = fraction[1:] if fraction.startswith("0") else fraction
        sec_text = f"{sec_int:02d}{frac}"
        stamp = f"{y:04d}-{mo:02d}-{d:02d} {hh:02d}:{mm:02d}:{sec_text}"
        return stamp, scalar
    except (ValueError, InvalidOperation, OverflowError):
        return None, None


def parse_epoch_line(line: str) -> dict:
    # A3 fields: >, year/month/day/hour/min/sec, flag, record count,
    # six spare spaces, and optional F15.12 receiver-clock offset.
    year = line[2:6].strip() if len(line) >= 6 else ""
    time_tokens: list[str] = []
    if year:
        time_tokens = [
            year, line[7:9].strip(), line[10:12].strip(),
            line[13:15].strip(), line[16:18].strip(), line[18:29].strip(),
        ]
    stamp, scalar = parse_stamp_tokens(time_tokens)
    try:
        flag = int(line[31:32].strip())
    except (ValueError, IndexError):
        flag = None
    try:
        record_count = int(line[32:35].strip())
    except (ValueError, IndexError):
        record_count = None
    clock_raw = line[41:56].strip() if len(line) > 41 else ""
    clock_value = None
    if clock_raw:
        try:
            clock_value = str(Decimal(clock_raw))
        except InvalidOperation:
            clock_value = None
    return {
        "stamp": stamp,
        "scalar": scalar,
        "flag": flag,
        "record_count": record_count,
        "clock_raw": clock_raw or None,
        "clock_value_seconds": clock_value,
    }


def parse_time_header(line: str) -> dict | None:
    words = text_before_label(line).split()
    stamp, scalar = parse_stamp_tokens(words)
    if not stamp:
        return None
    return {
        "stamp": stamp,
        "time_system": words[6] if len(words) > 6 else None,
        "scalar": scalar,
        "raw_value": text_before_label(line).strip(),
    }


def feed_obs_type_header(line: str, active: dict, pending: list[str | None]) -> None:
    label = label_of(line)
    if label != "SYS / # / OBS TYPES":
        pending[0] = None
        return
    payload = text_before_label(line).ljust(60)
    sys = payload[0]
    count_text = payload[1:6].strip()
    if sys.isalpha() and count_text.isdigit():
        count = int(count_text)
        codes = payload[6:].split()
        active[sys] = {"declared_count": count, "types": codes}
        pending[0] = sys if len(codes) < count else None
    elif pending[0]:
        current = active[pending[0]]
        current["types"].extend(payload[6:].split())
        if len(current["types"]) >= current["declared_count"]:
            pending[0] = None


def parse_initial_header(lines: list[str]) -> dict:
    active: dict = {}
    pending: list[str | None] = [None]
    header = {
        "version": None,
        "file_type_system": None,
        "interval_seconds": None,
        "time_of_first_obs": None,
        "time_of_last_obs": None,
        "declared_satellite_count": None,
        "receiver_clock_offset_applied": None,
        "prn_observation_count_records": 0,
        "label_start_column_counts": Counter(),
        "non_column_61_labels": [],
        "known_labels_found": Counter(),
        "raw_lines": len(lines),
    }
    for line in lines:
        label = label_of(line)
        if label in KNOWN_LABELS:
            offset = line.find(label)
            header["known_labels_found"][label] += 1
            header["label_start_column_counts"][str(offset + 1)] += 1
            if offset != 60:
                header["non_column_61_labels"].append({
                    "label": label,
                    "observed_start_column": offset + 1,
                    "line": line[:100],
                })
        feed_obs_type_header(line, active, pending)
        if label == "RINEX VERSION / TYPE":
            header["version"] = text_before_label(line)[:9].strip()
            header["file_type_system"] = text_before_label(line)[20:40].strip()
        elif label == "INTERVAL":
            try:
                header["interval_seconds"] = str(Decimal(text_before_label(line).strip()))
            except InvalidOperation:
                header["interval_seconds"] = text_before_label(line).strip()
        elif label == "TIME OF FIRST OBS":
            header["time_of_first_obs"] = parse_time_header(line)
        elif label == "TIME OF LAST OBS":
            header["time_of_last_obs"] = parse_time_header(line)
        elif label == "# OF SATELLITES":
            header["declared_satellite_count"] = text_before_label(line).strip()
        elif label == "PRN / # OF OBS":
            header["prn_observation_count_records"] += 1
        elif label == "RCV CLOCK OFFS APPL":
            header["receiver_clock_offset_applied"] = text_before_label(line).strip()
    header["obs_types_by_system"] = active
    return header


def new_system_stats() -> dict:
    return {
        "satellite_observation_records": 0,
        "unique_sv_ids": set(),
        "physical_line_length_histogram": Counter(),
        "payload_length_mod_16_histogram": Counter(),
        "expected_max_line_length": None,
        "short_rows": 0,
        "exact_expected_width_rows": 0,
        "overlong_rows": 0,
        "partial_final_field_rows": 0,
        "right_trim_compatible_final_value_rows": 0,
        "right_trim_ambiguous_final_rows": 0,
        "fully_omitted_trailing_fields": 0,
        "nonempty_fields": 0,
        "blank_fields": 0,
        "zero_numeric_fields": 0,
        "invalid_numeric_values": 0,
        "invalid_f14_3_values": 0,
        "observation_values_by_type": defaultdict(Counter),
        "lli_by_phase_type": defaultdict(Counter),
        "lli_bits_by_phase_type": defaultdict(Counter),
        "invalid_lli_by_phase_type": Counter(),
        "unexpected_lli_on_nonphase": Counter(),
        "ssi_by_type": defaultdict(Counter),
        "invalid_ssi_by_type": Counter(),
        "overwide_records_examples": [],
        "bad_record_examples": [],
    }


def decimal_str(value: Decimal | None) -> str | None:
    return format(value.normalize(), "f") if value is not None else None


def parse_observation_record(
    line: str,
    epoch_stamp: str | None,
    sys_stats: dict,
    active_obs_types: dict,
    errors: list,
) -> tuple[str, str] | None:
    match = SAT_ID.match(line)
    if not match:
        return None
    sys = match.group(1)
    sv = line[:3]
    spec = active_obs_types.get(sys)
    if not spec:
        errors.append({"kind": "system_not_declared_in_header", "sv": sv, "stamp": epoch_stamp})
        return sys, sv

    expected_n = spec["declared_count"]
    codes = spec["types"]
    if len(codes) != expected_n:
        codes = codes[:expected_n] + [
            f"UNDECLARED_{i + 1}" for i in range(max(0, expected_n - len(codes)))
        ]
    expected_width = 3 + OBS_SLOT_WIDTH * expected_n
    stats = sys_stats[sys]
    stats["satellite_observation_records"] += 1
    stats["unique_sv_ids"].add(sv)
    stats["physical_line_length_histogram"][str(len(line))] += 1
    stats["expected_max_line_length"] = expected_width

    if len(line) < expected_width:
        stats["short_rows"] += 1
    elif len(line) == expected_width:
        stats["exact_expected_width_rows"] += 1
    else:
        stats["overlong_rows"] += 1
        if len(stats["overwide_records_examples"]) < 5:
            stats["overwide_records_examples"].append({
                "stamp": epoch_stamp, "sv": sv,
                "length": len(line), "expected": expected_width,
            })
        errors.append({
            "kind": "record_longer_than_declared_arity",
            "stamp": epoch_stamp, "sv": sv,
            "length": len(line), "expected": expected_width,
        })

    tail = line[3:]
    tail_remainder = len(tail) % OBS_SLOT_WIDTH
    stats["payload_length_mod_16_histogram"][str(tail_remainder)] += 1
    if tail_remainder:
        stats["partial_final_field_rows"] += 1
        final_fragment = tail[-tail_remainder:]
        if tail_remainder == OBS_VALUE_WIDTH and VALUE_F14_3.fullmatch(final_fragment.strip()):
            stats["right_trim_compatible_final_value_rows"] += 1
        else:
            stats["right_trim_ambiguous_final_rows"] += 1
    for index, code in enumerate(codes):
        start = index * OBS_SLOT_WIDTH
        if start >= len(tail):
            stats["fully_omitted_trailing_fields"] += 1
        chunk = tail[start : start + OBS_SLOT_WIDTH].ljust(OBS_SLOT_WIDTH)
        value_text = chunk[:OBS_VALUE_WIDTH].strip()
        lli_char = chunk[14]
        ssi_char = chunk[15]

        value_counter = stats["observation_values_by_type"][code]
        value_counter["total_fields"] += 1
        if value_text:
            value_counter["nonempty_fields"] += 1
            stats["nonempty_fields"] += 1
            try:
                number = Decimal(value_text.replace("D", "E").replace("d", "e"))
                if not number.is_finite():
                    raise ValueError("not finite")
                if not VALUE_F14_3.fullmatch(value_text):
                    value_counter["invalid_f14_3_format"] += 1
                    stats["invalid_f14_3_values"] += 1
                    if len(stats["bad_record_examples"]) < 10:
                        stats["bad_record_examples"].append({
                            "stamp": epoch_stamp, "sv": sv, "type": code,
                            "value": value_text, "issue": "not F14.3 lexical form",
                        })
                    errors.append({
                        "kind": "observation_value_not_f14_3",
                        "stamp": epoch_stamp, "sv": sv, "type": code, "value": value_text,
                    })
                if number == 0:
                    value_counter["zero_numeric_fields"] += 1
                    stats["zero_numeric_fields"] += 1
            except (InvalidOperation, ValueError, OverflowError):
                value_counter["invalid_numeric"] += 1
                stats["invalid_numeric_values"] += 1
                if len(stats["bad_record_examples"]) < 5:
                    stats["bad_record_examples"].append({
                        "stamp": epoch_stamp, "sv": sv, "type": code, "value": value_text,
                    })
                errors.append({
                    "kind": "non_numeric_observation_value",
                    "stamp": epoch_stamp, "sv": sv, "type": code, "value": value_text,
                })
        else:
            value_counter["blank_fields"] += 1
            stats["blank_fields"] += 1

        if code.startswith("L"):
            lli_counter = stats["lli_by_phase_type"][code]
            lli_key = lli_char if lli_char.strip() else "blank"
            lli_counter[lli_key] += 1
            if lli_char.strip() and lli_char not in LLI_VALUES:
                stats["invalid_lli_by_phase_type"][code] += 1
                errors.append({
                    "kind": "invalid_phase_lli",
                    "stamp": epoch_stamp, "sv": sv, "type": code, "lli": lli_char,
                })
            elif lli_char.strip():
                value = int(lli_char)
                if value & 1:
                    stats["lli_bits_by_phase_type"][code]["bit0_cycle_slip_possible"] += 1
                if value & 2:
                    stats["lli_bits_by_phase_type"][code]["bit1_half_cycle_possible"] += 1
                if value & 4:
                    stats["lli_bits_by_phase_type"][code]["bit2_boc_tracking"] += 1
        elif lli_char.strip():
            stats["unexpected_lli_on_nonphase"][code] += 1
            errors.append({
                "kind": "lli_present_on_nonphase_observable",
                "stamp": epoch_stamp, "sv": sv, "type": code, "lli": lli_char,
            })

        ssi_counter = stats["ssi_by_type"][code]
        ssi_key = ssi_char if ssi_char.strip() else "blank"
        ssi_counter[ssi_key] += 1
        if ssi_char.strip() and ssi_char not in SSI_VALUES:
            stats["invalid_ssi_by_type"][code] += 1
            errors.append({
                "kind": "invalid_ssi",
                "stamp": epoch_stamp, "sv": sv, "type": code, "ssi": ssi_char,
            })
    return sys, sv


def finalize_system_stats(stats_by_system: dict) -> dict:
    out = {}
    for sys, stats in sorted(stats_by_system.items()):
        lengths = [int(x) for x in stats["physical_line_length_histogram"]]
        out[sys] = {
            **{k: v for k, v in stats.items() if k not in {
                "unique_sv_ids", "physical_line_length_histogram",
                "payload_length_mod_16_histogram",
                "observation_values_by_type", "lli_by_phase_type",
                "lli_bits_by_phase_type", "invalid_lli_by_phase_type",
                "unexpected_lli_on_nonphase", "ssi_by_type",
                "invalid_ssi_by_type",
            }},
            "unique_sv_ids": sorted(stats["unique_sv_ids"]),
            "unique_sv_count": len(stats["unique_sv_ids"]),
            "min_physical_line_length": min(lengths) if lengths else None,
            "max_physical_line_length": max(lengths) if lengths else None,
            "physical_line_length_histogram": dict(sorted(
                stats["physical_line_length_histogram"].items(), key=lambda kv: int(kv[0])
            )),
            "payload_length_mod_16_histogram": dict(sorted(
                stats["payload_length_mod_16_histogram"].items(), key=lambda kv: int(kv[0])
            )),
            "observation_values_by_type": {
                k: dict(v) for k, v in sorted(stats["observation_values_by_type"].items())
            },
            "lli_by_phase_type": {
                k: dict(v) for k, v in sorted(stats["lli_by_phase_type"].items())
            },
            "lli_bits_by_phase_type": {
                k: dict(v) for k, v in sorted(stats["lli_bits_by_phase_type"].items())
            },
            "invalid_lli_by_phase_type": dict(stats["invalid_lli_by_phase_type"]),
            "unexpected_lli_on_nonphase": dict(stats["unexpected_lli_on_nonphase"]),
            "ssi_by_type": {
                k: dict(v) for k, v in sorted(stats["ssi_by_type"].items())
            },
            "invalid_ssi_by_type": dict(stats["invalid_ssi_by_type"]),
        }
    return out


def analyze(path: Path) -> dict:
    if path.stat().st_size > 256 * 1024 * 1024:
        raise ValueError("Input exceeds the 256 MiB research cap")
    input_hash = sha256_file(path)
    with path.open("r", encoding="ascii", newline="") as f:
        header_lines = []
        for raw in f:
            line = raw.rstrip("\r\n")
            header_lines.append(line)
            if label_of(line) == "END OF HEADER":
                break
        else:
            raise ValueError("Missing END OF HEADER")
        header = parse_initial_header(header_lines)
        initial_types = deepcopy(header["obs_types_by_system"])
        active_types = deepcopy(initial_types)
        header["obs_types_by_system"] = {
            sys: {
                "declared_count": item["declared_count"],
                "parsed_type_count": len(item["types"]),
                "type_count_matches": len(item["types"]) == item["declared_count"],
                "types": item["types"],
            }
            for sys, item in sorted(initial_types.items())
        }

        flags = Counter()
        event_descriptions = defaultdict(Counter)
        clock_offsets = Counter()
        clock_offset_examples = []
        normal_epochs = 0
        normal_rows = 0
        event_record_counts = Counter()
        event_expected_records = Counter()
        event_mismatches = []
        body_nonrecord_lines = Counter()
        epoch_declared_row_mismatches = []
        duplicate_sv_records = 0
        duplicate_examples = []
        unique_sv = set()
        unique_sv_by_system = defaultdict(set)
        rows_by_system = Counter()
        stats_by_system = defaultdict(new_system_stats)
        field_parse_errors = []
        ordinary_epoch_times = []
        ordinary_stamps = []
        epoch_line_length_histogram = Counter()
        unknown_epoch_flags = Counter()
        unknown_system_rows = Counter()
        pending_event = None
        current_epoch = None

        def finish_event_if_incomplete(next_stamp: str | None) -> None:
            nonlocal pending_event
            if pending_event and pending_event["remaining"] != 0:
                event_mismatches.append({
                    "stamp": pending_event["stamp"],
                    "flag": pending_event["flag"],
                    "expected_records": pending_event["expected"],
                    "records_seen": pending_event["seen"],
                    "interrupted_before": next_stamp,
                })
                pending_event = None

        for line_no, raw in enumerate(f, start=len(header_lines) + 1):
            line = raw.rstrip("\r\n")
            if line.startswith(">"):
                parsed = parse_epoch_line(line)
                stamp = parsed["stamp"]
                finish_event_if_incomplete(stamp)
                if current_epoch is not None and current_epoch["flag"] in (0, 1):
                    expected = current_epoch["record_count"]
                    actual = current_epoch["rows"]
                    if expected is not None and actual != expected:
                        epoch_declared_row_mismatches.append({
                            "stamp": current_epoch["stamp"],
                            "flag": current_epoch["flag"],
                            "declared": expected,
                            "actual": actual,
                        })
                flag = parsed["flag"]
                if flag is None:
                    field_parse_errors.append({
                        "kind": "unparseable_epoch_flag", "line": line_no, "raw": line,
                    })
                    current_epoch = None
                    continue
                flags[str(flag)] += 1
                event_descriptions[str(flag)][EPOCH_FLAG_SEMANTICS.get(flag, "unknown flag")] += 1
                epoch_line_length_histogram[str(len(line))] += 1
                if flag not in EPOCH_FLAG_SEMANTICS:
                    unknown_epoch_flags[str(flag)] += 1
                if parsed["clock_raw"]:
                    clock_offsets["present"] += 1
                    clock_offsets["raw_" + parsed["clock_raw"]] += 1
                    if len(clock_offset_examples) < 10:
                        clock_offset_examples.append({
                            "stamp": stamp, "raw_seconds": parsed["clock_raw"],
                            "parsed_seconds": parsed["clock_value_seconds"],
                        })
                else:
                    clock_offsets["absent"] += 1

                current_epoch = {
                    "stamp": stamp,
                    "scalar": parsed["scalar"],
                    "flag": flag,
                    "record_count": parsed["record_count"],
                    "rows": 0,
                    "seen_sv": set(),
                }
                if flag in (0, 1):
                    normal_epochs += 1
                    ordinary_stamps.append(stamp)
                    ordinary_epoch_times.append(parsed["scalar"])
                else:
                    expected = parsed["record_count"]
                    event_expected_records[str(flag)] += expected or 0
                    if expected:
                        pending_event = {
                            "flag": flag,
                            "stamp": stamp,
                            "expected": expected,
                            "remaining": expected,
                            "seen": 0,
                            "obs_type_pending": [None],
                        }
                continue

            if pending_event is not None and pending_event["remaining"] > 0:
                pending_event["remaining"] -= 1
                pending_event["seen"] += 1
                event_record_counts[str(pending_event["flag"])] += 1
                current_flag = pending_event["flag"]
                if current_flag == 4:
                    feed_obs_type_header(line, active_types, pending_event["obs_type_pending"])
                elif current_flag == 6 and SAT_ID.match(line):
                    event_descriptions["6"]["cycle_slip_satellite_records"] += 1
                continue

            if current_epoch is None or current_epoch["flag"] not in (0, 1, 6):
                if line.strip():
                    body_nonrecord_lines["outside_observation_epoch_or_special_block"] += 1
                continue

            match = SAT_ID.match(line)
            if not match:
                if line.strip():
                    body_nonrecord_lines["not_satellite_prefixed"] += 1
                continue
            sys, sv = match.group(1), line[:3]
            if sys not in initial_types:
                unknown_system_rows[sys] += 1
            if current_epoch["flag"] == 6:
                event_descriptions["6"]["cycle_slip_satellite_records"] += 1
                continue

            current_epoch["rows"] += 1
            normal_rows += 1
            rows_by_system[sys] += 1
            unique_sv.add(sv)
            unique_sv_by_system[sys].add(sv)
            if sv in current_epoch["seen_sv"]:
                duplicate_sv_records += 1
                if len(duplicate_examples) < 10:
                    duplicate_examples.append({
                        "stamp": current_epoch["stamp"], "sv": sv,
                        "flag": current_epoch["flag"], "line": line_no,
                    })
            current_epoch["seen_sv"].add(sv)
            parse_observation_record(
                line, current_epoch["stamp"], stats_by_system, active_types, field_parse_errors
            )

        finish_event_if_incomplete(None)
        if current_epoch is not None and current_epoch["flag"] in (0, 1):
            expected = current_epoch["record_count"]
            actual = current_epoch["rows"]
            if expected is not None and actual != expected:
                epoch_declared_row_mismatches.append({
                    "stamp": current_epoch["stamp"],
                    "flag": current_epoch["flag"],
                    "declared": expected,
                    "actual": actual,
                })

    def hist_gaps(times: list[Decimal]) -> dict:
        gaps = Counter()
        nonpositive = 0
        for a, b in zip(times, times[1:]):
            delta = b - a
            gaps[decimal_str(delta)] += 1
            if delta <= 0:
                nonpositive += 1
        return {
            "gap_seconds_histogram": dict(sorted(gaps.items())),
            "nonpositive_gap_count": nonpositive,
            "gap_count": max(0, len(times) - 1),
        }

    interval = None
    if header.get("interval_seconds") is not None:
        try:
            interval = Decimal(header["interval_seconds"])
        except InvalidOperation:
            interval = None
    first_body = ordinary_epoch_times[0] if ordinary_epoch_times else None
    grid_violations = 0
    if interval and interval > 0 and first_body is not None:
        for t in ordinary_epoch_times:
            if (t - first_body) % interval != 0:
                grid_violations += 1

    header_first = header.get("time_of_first_obs")
    header_last = header.get("time_of_last_obs")
    header_first_scalar = header_first["scalar"] if header_first else None
    header_last_scalar = header_last["scalar"] if header_last else None
    body_first_scalar = ordinary_epoch_times[0] if ordinary_epoch_times else None
    body_last_scalar = ordinary_epoch_times[-1] if ordinary_epoch_times else None
    header_declared_sat_count = None
    if header.get("declared_satellite_count"):
        try:
            header_declared_sat_count = int(header["declared_satellite_count"])
        except ValueError:
            pass

    header_output = {
        k: v for k, v in header.items() if k not in {
            "label_start_column_counts", "non_column_61_labels", "known_labels_found",
            "raw_lines", "obs_types_by_system",
        }
    }
    for time_key in ("time_of_first_obs", "time_of_last_obs"):
        if header_output.get(time_key):
            header_output[time_key] = {
                **header_output[time_key],
                "scalar": decimal_str(header_output[time_key]["scalar"]),
            }
    systems = finalize_system_stats(stats_by_system)
    warnings = []
    if header_declared_sat_count is not None and header_declared_sat_count != len(unique_sv):
        warnings.append({
            "kind": "header_unique_satellite_count_mismatch",
            "header_declared": header_declared_sat_count,
            "body_unique_sv": len(unique_sv),
            "difference": len(unique_sv) - header_declared_sat_count,
        })
    if header_declared_sat_count is not None and header["prn_observation_count_records"] == 0:
        warnings.append({
            "kind": "header_satellite_count_without_prn_observation_records",
            "header_declared_satellites": header_declared_sat_count,
            "prn_observation_count_records": 0,
        })
    if epoch_declared_row_mismatches:
        warnings.append({
            "kind": "epoch_satellite_count_does_not_match_following_rows",
            "count": len(epoch_declared_row_mismatches),
        })
    if duplicate_sv_records:
        warnings.append({"kind": "duplicate_sv_within_epoch", "count": duplicate_sv_records})
    if field_parse_errors:
        warnings.append({"kind": "field_or_record_parse_errors", "count": len(field_parse_errors)})
    if unknown_epoch_flags:
        warnings.append({"kind": "unknown_epoch_flags", "values": dict(unknown_epoch_flags)})

    return {
        "checker_name": "brux_rinex_reference",
        "checker_version": "0.1",
        "checker_sha256": sha256_file(Path(__file__)),
        "input": {"file": path.name, "bytes": path.stat().st_size, "sha256": input_hash},
        "spec_reference": {
            "url": SPEC_URL,
            "cached_file": "rinex_4.01.pdf",
            "cached_file_bytes": (Path(__file__).with_name("rinex_4.01.pdf").stat().st_size
                                   if Path(__file__).with_name("rinex_4.01.pdf").exists() else None),
            "cached_file_sha256": (sha256_file(Path(__file__).with_name("rinex_4.01.pdf"))
                                   if Path(__file__).with_name("rinex_4.01.pdf").exists() else None),
            "sections_used": ["5.3.2", "6.3", "6.5", "6.7", "6.7.1", "8.2 tables A2-A3"],
            "expected_observation_slot_width": OBS_SLOT_WIDTH,
            "observation_value_width": OBS_VALUE_WIDTH,
            "trailing_blank_records": "right-padding to declared arity is applied; section 6.3 permits trailing blanks to be removed",
        },
        "header": {
            **header_output,
            "obs_types_by_system": header["obs_types_by_system"],
            "known_label_start_columns": dict(header["label_start_column_counts"]),
            "known_label_start_columns_are_61": not bool(header["non_column_61_labels"]),
            "non_column_61_labels": header["non_column_61_labels"],
            "known_labels_found": dict(header["known_labels_found"]),
        },
        "body": {
            "epoch_line_count": sum(flags.values()),
            "epoch_flags": dict(flags),
            "epoch_flag_semantics": {k: dict(v) for k, v in event_descriptions.items()},
            "normal_observation_epoch_count": normal_epochs,
            "normal_epochs_by_flag": {k: flags.get(k, 0) for k in ("0", "1")},
            "power_failure_epoch_count": flags.get("1", 0),
            "cycle_slip_epoch_count": flags.get("6", 0),
            "special_event_record_counts_by_flag": dict(event_record_counts),
            "special_event_expected_record_counts_by_flag": dict(event_expected_records),
            "special_event_record_count_mismatches": event_mismatches,
            "ordinary_epoch_first_stamp_raw": ordinary_stamps[0] if ordinary_stamps else None,
            "ordinary_epoch_last_stamp_raw": ordinary_stamps[-1] if ordinary_stamps else None,
            "time_system_label": header_first.get("time_system") if header_first else None,
            "time_stamps_converted_to_utc": False,
            "body_first_matches_header_first": (
                header_first_scalar == body_first_scalar if header_first_scalar is not None else None
            ),
            "body_last_matches_header_last": (
                header_last_scalar == body_last_scalar if header_last_scalar is not None else None
            ),
            "interval_seconds_declared": decimal_str(interval),
            **hist_gaps(ordinary_epoch_times),
            "grid_violations_relative_to_first_epoch": grid_violations,
            "receiver_clock_offsets": {
                "record_count_present": clock_offsets.get("present", 0),
                "record_count_absent": clock_offsets.get("absent", 0),
                "raw_value_histogram": {
                    k[4:]: v for k, v in clock_offsets.items() if k.startswith("raw_")
                },
                "examples": clock_offset_examples,
            },
            "satellite_observation_record_count": normal_rows,
            "satellite_observation_records_by_system": dict(rows_by_system),
            "unique_sv_count": len(unique_sv),
            "unique_sv_count_by_system": {
                sys: len(ids) for sys, ids in sorted(unique_sv_by_system.items())
            },
            "unique_sv_ids": sorted(unique_sv),
            "unique_sv_ids_by_system": {
                sys: sorted(ids) for sys, ids in sorted(unique_sv_by_system.items())
            },
            "duplicate_sv_records_within_epoch": duplicate_sv_records,
            "duplicate_sv_examples": duplicate_examples,
            "epoch_declared_satellite_row_mismatch_count": len(epoch_declared_row_mismatches),
            "epoch_declared_satellite_row_mismatch_examples": epoch_declared_row_mismatches[:10],
            "unknown_system_rows": dict(unknown_system_rows),
            "body_nonrecord_line_counts": dict(body_nonrecord_lines),
            "epoch_line_length_histogram": dict(sorted(
                epoch_line_length_histogram.items(), key=lambda kv: int(kv[0])
            )),
            "systems": systems,
            "nonempty_fields_total": sum(
                system["nonempty_fields"] for system in systems.values()
            ),
            "blank_fields_total": sum(
                system["blank_fields"] for system in systems.values()
            ),
            "zero_numeric_fields_total": sum(
                system["zero_numeric_fields"] for system in systems.values()
            ),
        },
        "warnings": warnings,
        "checker_limitations": [
            "stdlib research parser, not a complete RINEX 3/4 implementation",
            "does not validate geodetic correctness or signal-specific value ranges",
            "does not execute GeoRust, gnss-js, or another parser as a cross-check",
            "right-trimmed fields are interpreted as blank through padding; physically omitted trailing blanks cannot be distinguished from absent blank observations",
            "flag-4 dynamic observation declarations are observed and updated for subsequent records, but other inserted header semantics are not fully modeled",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", default=DEFAULT_INPUT)
    parser.add_argument("-o", "--output", default="brux_rinex_reference.json")
    args = parser.parse_args()
    base = Path(__file__).resolve().parent
    input_path = Path(args.input)
    if not input_path.is_absolute():
        input_path = base / input_path
    output_path = Path(args.output)
    if not output_path.is_absolute():
        output_path = base / output_path
    result = analyze(input_path)
    output_path.write_text(
        json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "output": str(output_path),
        "input_sha256": result["input"]["sha256"],
        "checker_sha256": result["checker_sha256"],
        "epoch_count": result["body"]["normal_observation_epoch_count"],
        "observation_rows": result["body"]["satellite_observation_record_count"],
        "warnings": result["warnings"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()

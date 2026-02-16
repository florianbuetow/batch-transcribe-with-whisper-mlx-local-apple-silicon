#!/usr/bin/env python3
"""Generate silence_map.json from FFmpeg silence detection log.

Parses silence_start/silence_end pairs from FFmpeg stderr output and produces
a JSON file mapping trimmed audio timestamps back to original audio timestamps.

Usage:
    uv run python scripts/generate_silence_map.py <silence_log> <duration> <source_file> <output_json>
"""

import json
import re
import sys
from pathlib import Path


def parse_silence_log(log_path: str) -> list[tuple[float, float]]:
    """Parse FFmpeg silence log into list of (start, end) silence intervals."""
    silence_periods: list[tuple[float, float]] = []
    current_start: float | None = None

    with open(log_path) as f:
        for line in f:
            if "silence_start:" in line:
                match = re.search(r"silence_start:\s*([\d.]+)", line)
                if match:
                    current_start = float(match.group(1))
            elif "silence_end:" in line:
                match = re.search(r"silence_end:\s*([\d.]+)", line)
                if match and current_start is not None:
                    silence_periods.append((current_start, float(match.group(1))))
                    current_start = None

    return silence_periods


def build_kept_segments(
    silence_periods: list[tuple[float, float]], duration: float
) -> tuple[list[dict[str, float]], float]:
    """Invert silence periods into kept speech segments with trimmed timestamps.

    Returns:
        Tuple of (kept_segments list, trimmed_duration).
    """
    kept_segments: list[dict[str, float]] = []
    prev_end = 0.0
    trimmed_cursor = 0.0

    for silence_start, silence_end in silence_periods:
        if silence_start > prev_end:
            segment_duration = silence_start - prev_end
            kept_segments.append(
                {
                    "trimmed_start": round(trimmed_cursor, 6),
                    "trimmed_end": round(trimmed_cursor + segment_duration, 6),
                    "original_start": round(prev_end, 6),
                    "original_end": round(silence_start, 6),
                }
            )
            trimmed_cursor += segment_duration
        prev_end = silence_end

    # Final segment after last silence
    if prev_end < duration:
        segment_duration = duration - prev_end
        kept_segments.append(
            {
                "trimmed_start": round(trimmed_cursor, 6),
                "trimmed_end": round(trimmed_cursor + segment_duration, 6),
                "original_start": round(prev_end, 6),
                "original_end": round(duration, 6),
            }
        )
        trimmed_cursor += segment_duration

    return kept_segments, trimmed_cursor


def main() -> int:
    if len(sys.argv) < 5:
        print(
            f"Usage: {sys.argv[0]} <silence_log> <duration> <source_file> <output_json>"
            " [--threshold-db VALUE] [--min-duration VALUE]",
            file=sys.stderr,
        )
        return 1

    silence_log_path = sys.argv[1]
    duration = float(sys.argv[2])
    source_file = sys.argv[3]
    output_json_path = sys.argv[4]

    # Parse optional flags
    threshold_db = -40.0
    min_duration = 1.0
    i = 5
    while i < len(sys.argv):
        if sys.argv[i] == "--threshold-db" and i + 1 < len(sys.argv):
            threshold_db = float(sys.argv[i + 1])
            i += 2
        elif sys.argv[i] == "--min-duration" and i + 1 < len(sys.argv):
            min_duration = float(sys.argv[i + 1])
            i += 2
        else:
            i += 1

    silence_periods = parse_silence_log(silence_log_path)
    kept_segments, trimmed_duration = build_kept_segments(silence_periods, duration)

    silence_map = {
        "version": "1.0",
        "source_file": source_file,
        "audio_duration_original_seconds": round(duration, 6),
        "audio_duration_trimmed_seconds": round(trimmed_duration, 6),
        "silence_threshold_db": threshold_db,
        "silence_min_duration_seconds": min_duration,
        "kept_segments": kept_segments,
    }

    Path(output_json_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_json_path, "w") as f:
        json.dump(silence_map, f, indent=2)
        f.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())

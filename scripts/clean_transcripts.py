#!/usr/bin/env python3
"""Clean transcripts by removing hallucinations (repetitive patterns).

This script detects and removes hallucinations from SRT transcripts using:
1. Suffix array algorithm to find consecutive repetitions
2. SVM classifier to distinguish hallucinations from natural speech patterns

Output: Cleaned .srt and .txt files in transcripts_cleaned/[model]/ directory.

Usage:
    DATA_DIR=/path/to/data uv run python scripts/clean_transcripts.py
    DATA_DIR=/path/to/data MODEL=medium-en uv run python scripts/clean_transcripts.py
    DATA_DIR=/path/to/data VERBOSE=true uv run python scripts/clean_transcripts.py
"""

import os
import re
import sys
import unicodedata
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Any

import srt

# =============================================================================
# Configuration (hardcoded - no config file in this project)
# =============================================================================

# SVM classifier coefficients (trained on hallucination dataset)
COEF_REPETITIONS = 0.8888460000
COEF_SEQUENCE_LENGTH = 0.6665380000
INTERCEPT = -6.7770510000

# Detection parameters
MIN_K = 1  # Minimum phrase length in words
MIN_REPETITIONS = 5  # Minimum consecutive repetitions to consider
MIN_WINDOW_SIZE = 500  # Sliding window size in words
OVERLAP_PERCENT = 25.0  # Overlap between windows

# =============================================================================
# SRT Entry Dataclass
# =============================================================================


@dataclass(frozen=True)
class SRTEntry:
    """Single SRT subtitle entry with word position tracking."""

    index: int  # Original SRT entry index (1-based)
    start: timedelta  # Start timestamp
    end: timedelta  # End timestamp
    content: str  # Text content
    word_start: int  # Starting word position in concatenated text
    word_end: int  # Ending word position (exclusive)


# =============================================================================
# Hallucination Classifier
# =============================================================================


class HallucinationClassifier:
    """SVM-based hallucination classifier using trained model coefficients."""

    def __init__(self) -> None:
        self.coef_repetitions = COEF_REPETITIONS
        self.coef_sequence_length = COEF_SEQUENCE_LENGTH
        self.intercept = INTERCEPT

    def predict(self, repetitions: float, sequence_length: float) -> bool:
        """Predict if input is a hallucination.

        Args:
            repetitions: Number of consecutive repetitions.
            sequence_length: Length of repeated phrase (k = words).

        Returns:
            True if classified as hallucination, False otherwise.
        """
        score = self.decision_function(repetitions, sequence_length)
        return score > 0

    def decision_function(self, repetitions: float, sequence_length: float) -> float:
        """Compute raw SVM decision function score."""
        return (
            self.coef_repetitions * repetitions
            + self.coef_sequence_length * sequence_length
            + self.intercept
        )


# =============================================================================
# Repetition Detector
# =============================================================================


class RepetitionDetector:
    """Detect repetitive patterns using suffix array algorithm and ML classification."""

    _WS = re.compile(r"\s+")

    def __init__(self, min_k: int, min_repetitions: int) -> None:
        self.min_k = min_k
        self.min_repetitions = min_repetitions
        self.classifier = HallucinationClassifier()

    def prepare(self, text: str) -> str:
        """Normalize whitespace and remove invisible Unicode characters."""
        # Remove invisible Unicode formatting characters (category "C" = control/format)
        text = "".join(
            ch for ch in text if unicodedata.category(ch)[0] != "C" or ch in "\n\r\t "
        )
        # Normalize whitespace
        return self._WS.sub(" ", text).strip()

    def detect(self, text: str, min_k: int) -> list[list[int]]:
        """Detect repetitions and return list of [start, end, k].

        If multiple k exist for the same start point, only the largest k is kept.
        """
        cleaned_text = self.prepare(text)
        if not cleaned_text:
            return []

        words = cleaned_text.split()
        if len(words) < min_k * 2:
            return []

        # 1. Tokenize
        tokens, _ = self._tokenize(words)

        # 2. Build Suffix Array
        suffixes = list(range(len(tokens) - min_k + 1))
        suffixes.sort(key=lambda x: tokens[x:])

        # 3. Find all raw repetitions
        raw_results: list[list[int]] = []
        i = 0
        while i < len(suffixes) - 1:
            j = i + 1
            lcp_len = self._longest_common_prefix(tokens, suffixes[i], suffixes[j])

            if lcp_len >= min_k:
                match_indices = [suffixes[i], suffixes[j]]
                while j + 1 < len(suffixes):
                    if (
                        self._longest_common_prefix(tokens, suffixes[j], suffixes[j + 1])
                        >= lcp_len
                    ):
                        match_indices.append(suffixes[j + 1])
                        j += 1
                    else:
                        break

                raw_results.extend(
                    [[start_idx, start_idx + lcp_len, lcp_len] for start_idx in match_indices]
                )
                i = j
            else:
                i += 1

        # 4. Filter to keep only the largest k for overlapping starts
        raw_results.sort(key=lambda x: (x[0], -x[2]))

        final_results: list[list[int]] = []
        last_start = -1
        last_end = -1

        for start, end, k in raw_results:
            if start == last_start:
                continue
            if start < last_end and end <= last_end:
                continue

            final_results.append([start, end, k])
            last_start = start
            last_end = end

        return final_results

    def is_consecutive_repetition(self, words: list[str], start: int, end: int) -> bool:
        """Check if a phrase repeats immediately after itself."""
        phrase_length = end - start

        if end + phrase_length > len(words):
            return False

        phrase = words[start:end]
        next_phrase = words[end : end + phrase_length]

        return phrase == next_phrase

    def count_consecutive_repetitions(self, words: list[str], start: int, end: int) -> int:
        """Count how many times a phrase repeats consecutively."""
        phrase_length = end - start
        repetition_count = 1

        current_pos = end
        while current_pos + phrase_length <= len(words):
            next_phrase = words[current_pos : current_pos + phrase_length]
            original_phrase = words[start:end]

            if next_phrase == original_phrase:
                repetition_count += 1
                current_pos += phrase_length
            else:
                break

        return repetition_count

    def detect_hallucinations(self, text: str) -> list[list[int]]:
        """Detect hallucinations using ML classifier.

        Returns:
            List of [start, end, k, repetition_count] for qualifying patterns.
        """
        all_repetitions = self.detect(text, min_k=self.min_k)

        if not all_repetitions:
            return []

        cleaned_text = self.prepare(text)
        words = cleaned_text.split()

        hallucinations: list[list[int]] = []
        for start, end, k in all_repetitions:
            if self.is_consecutive_repetition(words, start, end):
                rep_count = self.count_consecutive_repetitions(words, start, end)

                if rep_count >= self.min_repetitions:
                    is_hallucination = self.classifier.predict(rep_count, k)
                    if is_hallucination:
                        hallucinations.append([start, end, k, rep_count])
                        break  # Stop after first detection in window

        return hallucinations

    def _tokenize(self, words: list[str]) -> tuple[list[int], dict[str, int]]:
        vocab: dict[str, int] = {}
        tokens: list[int] = []
        next_id = 0
        for word in words:
            if word not in vocab:
                vocab[word] = next_id
                next_id += 1
            tokens.append(vocab[word])
        return tokens, vocab

    def _longest_common_prefix(self, tokens: list[int], idx1: int, idx2: int) -> int:
        length = 0
        limit = min(len(tokens) - idx1, len(tokens) - idx2)
        while length < limit:
            if tokens[idx1 + length] == tokens[idx2 + length]:
                length += 1
            else:
                break
        return length


# =============================================================================
# SRT Utilities
# =============================================================================


def parse_srt_file(srt_path: Path) -> list[SRTEntry]:
    """Parse SRT file into list of entries with word position mapping."""
    content = srt_path.read_text(encoding="utf-8")
    subtitles = list(srt.parse(content))

    entries: list[SRTEntry] = []
    word_pos = 0
    for sub in subtitles:
        words = sub.content.split()
        word_count = len(words)
        start_td = timedelta(seconds=sub.start.total_seconds())
        end_td = timedelta(seconds=sub.end.total_seconds())
        entries.append(
            SRTEntry(
                index=sub.index,
                start=start_td,
                end=end_td,
                content=sub.content,
                word_start=word_pos,
                word_end=word_pos + word_count,
            )
        )
        word_pos += word_count
    return entries


def entries_to_text(entries: list[SRTEntry]) -> str:
    """Concatenate SRT entries into plain text."""
    return " ".join(e.content for e in entries)


def get_total_words(entries: list[SRTEntry]) -> int:
    """Get total word count across all entries."""
    if not entries:
        return 0
    return entries[-1].word_end


# =============================================================================
# Text Cleaning
# =============================================================================

_WS = re.compile(r"\s+")


def normalize_whitespace(text: str) -> str:
    """Normalize whitespace and remove invisible Unicode characters."""
    text = "".join(
        ch for ch in text if unicodedata.category(ch)[0] != "C" or ch in "\n\r\t "
    )
    return _WS.sub(" ", text).strip()


def remove_consecutive_repetitions(text: str, pattern: str, repetition_count: int) -> str:
    """Remove consecutive repetitions of a pattern.

    Args:
        text: Text containing repetitions.
        pattern: The repeating pattern to remove.
        repetition_count: How many times the pattern repeats.

    Returns:
        Cleaned text with pattern reduced to single occurrence.
    """
    normalized_text = normalize_whitespace(text)
    normalized_pattern = normalize_whitespace(pattern)

    # Build repeated pattern string
    repeated_pattern = (normalized_pattern + " ") * repetition_count
    repeated_pattern = repeated_pattern.strip()

    # Replace with single occurrence
    cleaned = normalized_text.replace(repeated_pattern, normalized_pattern)
    return cleaned


# =============================================================================
# Main Processing Logic
# =============================================================================


def find_srt_files(data_dir: Path, model_filter: str | None) -> list[Path]:
    """Find all SRT files to process.

    Args:
        data_dir: Data directory path.
        model_filter: Optional model name to filter (e.g., "medium-en").

    Returns:
        List of SRT file paths.
    """
    srt_files: list[Path] = []

    output_dir = data_dir / "output"
    if not output_dir.exists():
        return srt_files

    for category_dir in output_dir.iterdir():
        if not category_dir.is_dir():
            continue

        transcripts_dir = category_dir / "transcripts"
        if not transcripts_dir.exists():
            continue

        for model_dir in transcripts_dir.iterdir():
            if not model_dir.is_dir():
                continue

            # Filter by model if specified
            if model_filter and model_dir.name != model_filter:
                continue

            for srt_file in model_dir.glob("*.srt"):
                if not srt_file.name.startswith("._"):
                    srt_files.append(srt_file)

    return srt_files


def process_srt_file(
    srt_path: Path,
    output_dir: Path,
    detector: RepetitionDetector,
    verbose: bool,
) -> tuple[bool, int, str | None]:
    """Process a single SRT file.

    Args:
        srt_path: Path to input SRT file.
        output_dir: Output directory for cleaned files.
        detector: RepetitionDetector instance.
        verbose: Whether to print detailed progress.

    Returns:
        Tuple of (had_hallucinations, hallucination_count, error_message).
    """
    try:
        entries = parse_srt_file(srt_path)
    except Exception as e:
        return False, 0, f"Failed to parse SRT: {e}"

    if not entries:
        return False, 0, None

    # Sliding window detection
    total_words = get_total_words(entries)
    window_size = MIN_WINDOW_SIZE
    overlap = int(window_size * OVERLAP_PERCENT / 100)

    all_hallucinations: list[dict[str, Any]] = []
    window_start = 0

    while window_start < total_words:
        # Collect entries for this window
        window_entries = [
            e
            for e in entries
            if e.word_end > window_start
            and e.word_start < window_start + window_size
        ]

        if not window_entries:
            window_start += window_size - overlap
            continue

        window_text = entries_to_text(window_entries)
        word_count = len(window_text.split())

        if word_count < window_size and window_start == 0:
            # First window is smaller than min size, process anyway
            pass
        elif word_count < window_size // 2:
            # Window too small, skip
            window_start += window_size - overlap
            continue

        # Detect hallucinations in window
        hallucinations = detector.detect_hallucinations(window_text)

        if hallucinations:
            for start, end, k, rep_count in hallucinations:
                # Get the pattern
                words = detector.prepare(window_text).split()
                pattern = " ".join(words[start:end])

                all_hallucinations.append(
                    {
                        "start_entry_idx": window_entries[0].index - 1,
                        "end_entry_idx": window_entries[-1].index - 1,
                        "pattern": pattern,
                        "repetition_count": rep_count,
                        "sequence_length": k,
                    }
                )

        window_start += window_size - overlap

    if not all_hallucinations:
        # No hallucinations - copy file unchanged
        output_srt = output_dir / srt_path.name
        output_txt = output_dir / srt_path.with_suffix(".txt").name

        output_dir.mkdir(parents=True, exist_ok=True)
        output_srt.write_text(srt_path.read_text(encoding="utf-8"), encoding="utf-8")

        # Generate TXT from original
        txt_content = entries_to_text(entries)
        output_txt.write_text(txt_content, encoding="utf-8")

        return False, 0, None

    # Clean hallucinations
    if verbose:
        for h in all_hallucinations:
            pattern_preview = str(h["pattern"])[:50]
            print(f"    Found: \"{pattern_preview}...\" ({h['repetition_count']}x)")

    # Parse SRT for cleaning
    srt_content = srt_path.read_text(encoding="utf-8")
    subtitles = list(srt.parse(srt_content))

    for hallucination in all_hallucinations:
        pattern: str = str(hallucination["pattern"])
        rep_count: int = int(hallucination["repetition_count"])

        # Find affected subtitles (those containing the pattern)
        full_text = " ".join(s.content for s in subtitles)
        normalized_full = normalize_whitespace(full_text)

        # Build repeated pattern
        normalized_pattern = normalize_whitespace(pattern)
        repeated = (normalized_pattern + " ") * rep_count
        repeated = repeated.strip()

        if repeated in normalized_full:
            # Find which subtitles are affected
            affected_indices = []
            for idx, sub in enumerate(subtitles):
                if normalized_pattern in normalize_whitespace(sub.content):
                    affected_indices.append(idx)

            if affected_indices:
                # Collect text from affected entries
                window_content = " ".join(str(subtitles[i].content) for i in affected_indices)

                # Clean
                cleaned_content = remove_consecutive_repetitions(
                    window_content, pattern, rep_count
                )

                # Put cleaned text in first affected subtitle, clear others
                subtitles[affected_indices[0]] = srt.Subtitle(
                    index=subtitles[affected_indices[0]].index,
                    start=subtitles[affected_indices[0]].start,
                    end=subtitles[affected_indices[0]].end,
                    content=cleaned_content,
                )

                for idx in affected_indices[1:]:
                    subtitles[idx] = srt.Subtitle(
                        index=subtitles[idx].index,
                        start=subtitles[idx].start,
                        end=subtitles[idx].end,
                        content="",
                    )

    # Remove empty subtitles and reindex
    subtitles = [s for s in subtitles if s.content.strip()]
    for new_idx, subtitle in enumerate(subtitles, start=1):
        subtitles[new_idx - 1] = srt.Subtitle(
            index=new_idx,
            start=subtitle.start,
            end=subtitle.end,
            content=subtitle.content,
        )

    # Write output files
    output_dir.mkdir(parents=True, exist_ok=True)

    output_srt = output_dir / srt_path.name
    cleaned_srt_content = srt.compose(subtitles)
    output_srt.write_text(cleaned_srt_content, encoding="utf-8")

    # Generate TXT from cleaned SRT
    output_txt = output_dir / srt_path.with_suffix(".txt").name
    txt_content = " ".join(s.content for s in subtitles)
    output_txt.write_text(txt_content, encoding="utf-8")

    return True, len(all_hallucinations), None


def main() -> int:
    """Main entry point."""
    # Get configuration from environment
    data_dir_str = os.environ.get("DATA_DIR")
    if not data_dir_str:
        print("Error: DATA_DIR environment variable not set", file=sys.stderr)
        return 1

    data_dir = Path(data_dir_str)
    if not data_dir.exists():
        print(f"Error: Data directory not found: {data_dir}", file=sys.stderr)
        return 1

    model_filter = os.environ.get("MODEL", "").strip() or None
    verbose = os.environ.get("VERBOSE", "").lower() == "true"

    # Find SRT files
    srt_files = find_srt_files(data_dir, model_filter)

    if not srt_files:
        if model_filter:
            print(f"No SRT files found for model: {model_filter}")
        else:
            print("No SRT files found")
        return 0

    print(f"Found {len(srt_files)} SRT file(s) to process")
    if model_filter:
        print(f"Filtering by model: {model_filter}")
    print()

    # Initialize detector
    detector = RepetitionDetector(min_k=MIN_K, min_repetitions=MIN_REPETITIONS)

    # Process files
    total_processed = 0
    total_cleaned = 0
    total_hallucinations = 0
    failures: list[tuple[str, str]] = []

    for srt_path in sorted(srt_files):
        # Determine output directory
        # input: data/output/[category]/transcripts/[model]/file.srt
        # output: data/output/[category]/transcripts_cleaned/[model]/file.srt
        relative_parts = srt_path.relative_to(data_dir / "output").parts
        category = relative_parts[0]
        model = relative_parts[2]  # transcripts/[model]/file.srt

        output_dir = data_dir / "output" / category / "transcripts_cleaned" / model

        if verbose:
            print(f"Processing: {category}/{model}/{srt_path.name}")

        had_hallucinations, hallucination_count, error = process_srt_file(
            srt_path, output_dir, detector, verbose
        )

        if error:
            failures.append((str(srt_path), error))
            if verbose:
                print(f"  Error: {error}")
        else:
            total_processed += 1
            if had_hallucinations:
                total_cleaned += 1
                total_hallucinations += hallucination_count
                if verbose:
                    print(f"  Cleaned {hallucination_count} hallucination(s)")
            elif verbose:
                print("  No hallucinations")

    # Print summary
    print()
    print("=" * 50)
    print("Summary")
    print("=" * 50)
    print(f"Files processed: {total_processed}")
    print(f"Files with hallucinations cleaned: {total_cleaned}")
    print(f"Total hallucinations removed: {total_hallucinations}")
    print(f"Files copied unchanged: {total_processed - total_cleaned}")

    if failures:
        print(f"\nFailures ({len(failures)}):")
        for filepath, error in failures:
            print(f"  {filepath}: {error}")

    output_base = data_dir / "output"
    print(f"\nOutput written to: {output_base}/*/transcripts_cleaned/")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

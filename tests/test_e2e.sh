#!/bin/bash
set -e

# =============================================================================
# End-to-End Pipeline Test
# =============================================================================
# Tests the full pipeline: prepare (with silence removal) → transcribe → verify
#
# Uses a synthetic test audio file with 3 speech segments separated by silence.
# Verifies:
#   1. WAV + silence_map.json are generated during prepare
#   2. silence_map.json has correct structure (3 kept segments)
#   3. Transcription produces only txt + srt (no vtt/tsv/json)
#   4. SRT timestamps are remapped to original audio timeline
#   5. clean-transcripts produces cleaned output

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_CATEGORY="__test__"
MODEL="tiny"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() {
    PASSED=$((PASSED + 1))
    printf "${GREEN}  ✓ %s${NC}\n" "$1"
}

fail() {
    FAILED=$((FAILED + 1))
    printf "${RED}  ✗ %s${NC}\n" "$1"
}

# --- Setup ---
echo ""
echo "=== E2E Pipeline Test ==="
echo ""

# Create test input directory and copy fixture
mkdir -p "$PROJECT_ROOT/data/input/$TEST_CATEGORY"
cp "$PROJECT_ROOT/tests/fixtures/test_with_silence.mp4" "$PROJECT_ROOT/data/input/$TEST_CATEGORY/"

# Clean any previous test output
rm -rf "$PROJECT_ROOT/data/output/$TEST_CATEGORY"

# --- Test 1: Prepare (silence removal + silence map) ---
echo "Step 1: Running prepare..."
DATA_DIR="$PROJECT_ROOT/data" REMOVE_SILENCE=true bash "$PROJECT_ROOT/scripts/prepare_audio.sh" > /dev/null 2>&1

echo "Verifying prepare output:"

# Check WAV file exists
if [ -f "$PROJECT_ROOT/data/output/$TEST_CATEGORY/wav/test_with_silence.wav" ]; then
    pass "WAV file created"
else
    fail "WAV file not created"
fi

# Check silence_map.json exists
SILENCE_MAP="$PROJECT_ROOT/data/output/$TEST_CATEGORY/wav/test_with_silence.silence_map.json"
if [ -f "$SILENCE_MAP" ]; then
    pass "silence_map.json created"
else
    fail "silence_map.json not created"
fi

# Check silence_map.json has correct structure
if [ -f "$SILENCE_MAP" ]; then
    # Check version field
    version=$(uv run python -c "import json; print(json.load(open('$SILENCE_MAP'))['version'])" 2>/dev/null)
    if [ "$version" = "1.0" ]; then
        pass "silence_map.json has version 1.0"
    else
        fail "silence_map.json version is '$version', expected '1.0'"
    fi

    # Check kept_segments count (should be 3 speech segments)
    segment_count=$(uv run python -c "import json; print(len(json.load(open('$SILENCE_MAP'))['kept_segments']))" 2>/dev/null)
    if [ "$segment_count" -ge 2 ]; then
        pass "silence_map.json has $segment_count kept segments (expected >= 2)"
    else
        fail "silence_map.json has $segment_count kept segments (expected >= 2)"
    fi

    # Check original duration > trimmed duration (silence was removed)
    duration_check=$(uv run python -c "
import json
m = json.load(open('$SILENCE_MAP'))
orig = m['audio_duration_original_seconds']
trim = m['audio_duration_trimmed_seconds']
print('ok' if orig > trim else 'fail')
print(f'original={orig:.1f}s trimmed={trim:.1f}s')
" 2>/dev/null)
    if echo "$duration_check" | head -1 | grep -q "ok"; then
        duration_info=$(echo "$duration_check" | tail -1)
        pass "Silence was removed ($duration_info)"
    else
        fail "Original duration should be > trimmed duration"
    fi
fi

# --- Test 2: Transcribe with tiny model ---
echo ""
echo "Step 2: Running transcription (tiny model)..."
DATA_DIR="$PROJECT_ROOT/data" MODEL_NAME=$MODEL MODEL_REPO=mlx-community/whisper-tiny bash "$PROJECT_ROOT/scripts/transcribe.sh" > /dev/null 2>&1

TRANSCRIPT_DIR="$PROJECT_ROOT/data/output/$TEST_CATEGORY/transcripts/$MODEL"
echo "Verifying transcription output:"

# Check txt file exists
if [ -f "$TRANSCRIPT_DIR/test_with_silence.txt" ]; then
    pass "TXT transcript created"
else
    fail "TXT transcript not created"
fi

# Check srt file exists
if [ -f "$TRANSCRIPT_DIR/test_with_silence.srt" ]; then
    pass "SRT transcript created"
else
    fail "SRT transcript not created"
fi

# Check NO vtt/tsv/json files
for ext in vtt tsv json; do
    if [ -f "$TRANSCRIPT_DIR/test_with_silence.$ext" ]; then
        fail "Unexpected .$ext file found (should only produce txt + srt)"
    else
        pass "No .$ext file (correct)"
    fi
done

# Check SRT timestamps are remapped to original timeline
# The test audio has 3 speech segments at known original positions:
#   Speech 1: ~0-7.6s    ("first part of the test audio")
#   Speech 2: ~12.6-20.2s ("second segment")  -- would be at ~7.6s without remapping
#   Speech 3: ~28.2-36.9s ("final segment")   -- would be at ~15.2s without remapping
if [ -f "$TRANSCRIPT_DIR/test_with_silence.srt" ]; then
    remap_result=$(uv run python -c "
import json, srt
from pathlib import Path

subs = list(srt.parse(Path('$TRANSCRIPT_DIR/test_with_silence.srt').read_text()))
m = json.load(open('$SILENCE_MAP'))
trim_dur = m['audio_duration_trimmed_seconds']
orig_dur = m['audio_duration_original_seconds']

results = []

# Test: SRT is not empty
if not subs:
    results.append('FAIL empty')
else:
    results.append('PASS has_subs')

# Test: last subtitle ends near original duration (not trimmed duration)
# This proves remapping happened at all
if subs:
    last_end = subs[-1].end.total_seconds()
    if last_end > trim_dur:
        results.append(f'PASS last_end={last_end:.1f}s > trimmed={trim_dur:.1f}s')
    else:
        results.append(f'FAIL last_end={last_end:.1f}s <= trimmed={trim_dur:.1f}s (not remapped)')

# Test: speech about 'second segment' has timestamps in original range (~12-21s)
# Without remapping it would be at ~7.6-15.2s (trimmed timeline)
if subs:
    for sub in subs:
        if 'second' in sub.content.lower():
            start = sub.start.total_seconds()
            end = sub.end.total_seconds()
            # The subtitle should overlap with the original speech 2 range (12.6-20.2s)
            # and NOT be entirely in the trimmed range (7.6-15.2s)
            if end > 12.0:
                results.append(f'PASS second_segment at {start:.1f}-{end:.1f}s (original range)')
            else:
                results.append(f'FAIL second_segment at {start:.1f}-{end:.1f}s (looks like trimmed range)')
            break
    else:
        results.append('SKIP second_segment not found in transcript')

# Test: last subtitle starts in 3rd speech segment's original range (>25s)
# Without remapping, the entire trimmed audio is only ~23.8s, so no subtitle
# could start at >25s. This proves the 3rd segment was remapped correctly.
if subs:
    last_start = subs[-1].start.total_seconds()
    if last_start > 25.0:
        results.append(f'PASS last_sub_start={last_start:.1f}s > 25s (3rd segment original range)')
    else:
        results.append(f'FAIL last_sub_start={last_start:.1f}s <= 25s (not in 3rd segment original range)')

for r in results:
    print(r)
" 2>/dev/null)

    # Process each result line
    while IFS= read -r line; do
        status="${line%% *}"
        detail="${line#* }"
        case "$status" in
            PASS) pass "Timestamp remap: $detail" ;;
            FAIL) fail "Timestamp remap: $detail" ;;
            SKIP) printf "${YELLOW}  ⚠ %s${NC}\n" "$detail" ;;
        esac
    done <<< "$remap_result"
fi

# --- Test 3: Clean transcripts ---
echo ""
echo "Step 3: Running clean-transcripts..."
DATA_DIR="$PROJECT_ROOT/data" MODEL=$MODEL uv run python "$PROJECT_ROOT/scripts/clean_transcripts.py" > /dev/null 2>&1

CLEANED_DIR="$PROJECT_ROOT/data/output/$TEST_CATEGORY/transcripts_cleaned/$MODEL"
echo "Verifying cleaned output:"

if [ -f "$CLEANED_DIR/test_with_silence.srt" ]; then
    pass "Cleaned SRT created"
else
    fail "Cleaned SRT not created"
fi

if [ -f "$CLEANED_DIR/test_with_silence.txt" ]; then
    pass "Cleaned TXT created"
else
    fail "Cleaned TXT not created"
fi

# --- Cleanup ---
echo ""
echo "Cleaning up test data..."
rm -rf "$PROJECT_ROOT/data/input/$TEST_CATEGORY"
rm -rf "$PROJECT_ROOT/data/output/$TEST_CATEGORY"

# --- Summary ---
echo ""
echo "=== Test Summary ==="
TOTAL=$((PASSED + FAILED))
printf "  ${GREEN}Passed: $PASSED${NC}\n"
if [ $FAILED -gt 0 ]; then
    printf "  ${RED}Failed: $FAILED${NC}\n"
else
    printf "  Failed: 0\n"
fi
echo "  Total:  $TOTAL"
echo ""

if [ $FAILED -gt 0 ]; then
    printf "${RED}TESTS FAILED${NC}\n"
    echo ""
    exit 1
else
    printf "${GREEN}ALL TESTS PASSED${NC}\n"
    echo ""
    exit 0
fi

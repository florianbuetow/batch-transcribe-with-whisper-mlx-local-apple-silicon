#!/bin/bash

# --- Configuration ---
# Set this variable to the directory containing your data folders
# Or pass DATA_DIR as an environment variable
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/path/to/your/data/folder"
fi

# MP3 encoding parameters
MP3_BITRATE="128k"
MP3_SAMPLE_RATE="44100"

# VERBOSE: Set to "true" to show individual skip messages, otherwise show summary
# Default is "false" (summary only)
VERBOSE="${VERBOSE:-false}"
# --- End Configuration ---

# Check if DATA_DIR is set to the default value
if [ "$DATA_DIR" == "/path/to/your/data/folder" ]; then
    echo "🚨 ERROR: Please edit this script and set the DATA_DIR variable to your folder."
    exit 1
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo "🚨 ERROR: ffmpeg is not installed. Please install it (e.g., 'brew install ffmpeg')"
    exit 1
fi

# Detect number of CPU cores for optimal threading
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    NUM_THREADS=$(sysctl -n hw.ncpu)
else
    # Linux
    NUM_THREADS=$(nproc)
fi

echo "Compressing WAV files to MP3 ($MP3_BITRATE, $MP3_SAMPLE_RATE Hz) in: $DATA_DIR/output"
echo "=========================================="
echo ""

# Iterate over all category folders in output directory
find "$DATA_DIR/output" -mindepth 1 -maxdepth 1 -type d | while read -r category_dir; do
    category_name=$(basename "$category_dir")
    wav_dir="$category_dir/wav"

    # Skip categories that have no wav directory
    if [ ! -d "$wav_dir" ]; then
        continue
    fi

    echo "Processing category: $category_name"
    echo "---"

    # Create output directory for this category
    mkdir -p "$DATA_DIR/output/$category_name/mp3"

    # Counters for this category
    skipped_count=0
    converted_count=0

    # Process all WAV files (silence map .json files are not matched)
    while IFS= read -r -d '' wav_file; do

        # Get the base filename
        filename=$(basename "$wav_file")
        base_name="${filename%.*}"

        # Define the output .mp3 file path
        output_mp3="$DATA_DIR/output/$category_name/mp3/$base_name.mp3"

        # Check if output MP3 file already exists
        if [ -f "$output_mp3" ]; then
            skipped_count=$((skipped_count + 1))
            if [ "$VERBOSE" = "true" ]; then
                echo "  ⏭️  Skipping: $filename (MP3 already exists)"
                echo "  ---"
            fi
        else
            echo "  Processing: $filename"
            echo "    Encoding to output/$category_name/mp3/$base_name.mp3 (using $NUM_THREADS threads)..."

            ffmpeg -threads "$NUM_THREADS" -y -i "$wav_file" \
                -vn -ar "$MP3_SAMPLE_RATE" -c:a libmp3lame -b:a "$MP3_BITRATE" \
                -loglevel error \
                "$output_mp3" </dev/null
            ffmpeg_exit=$?

            # Verify the conversion before removing the source WAV.
            # Both gates must pass: ffmpeg exited cleanly AND the MP3 is not empty.
            if [ $ffmpeg_exit -ne 0 ]; then
                echo "    🚨 FAILED to compress $filename (ffmpeg exit code $ffmpeg_exit)"
                # Remove the partial MP3 so the next run retries instead of skipping it
                rm -f "$output_mp3"
                exit 1
            fi

            if [ ! -s "$output_mp3" ]; then
                echo "    🚨 FAILED to compress $filename (MP3 is empty)"
                rm -f "$output_mp3"
                exit 1
            fi

            # Verified: remove the source WAV (the silence map is kept)
            rm -f "$wav_file"

            converted_count=$((converted_count + 1))
            echo "    ✅ Done: $base_name.mp3 (WAV removed)"
            echo "  ---"
        fi

    done < <(find "$wav_dir" -maxdepth 1 -type f -iname "*.wav" -print0)

    # Print summary for this category
    if [ $converted_count -gt 0 ]; then
        echo "✅ Compressed $converted_count file(s)"
    fi
    if [ $skipped_count -gt 0 ]; then
        echo "⏭️  Skipped $skipped_count file(s) (MP3 already exists)"
    fi

    echo ""
done

echo "Audio compression complete."

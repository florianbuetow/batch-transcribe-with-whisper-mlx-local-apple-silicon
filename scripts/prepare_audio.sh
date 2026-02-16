#!/bin/bash

# --- Configuration ---
# Set this variable to the directory containing your data folders
# Or pass DATA_DIR as an environment variable
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/path/to/your/data/folder"
fi

# REMOVE_SILENCE: Set to "true" to remove silence from audio and generate silence_map.json
REMOVE_SILENCE="${REMOVE_SILENCE:-true}"

# Silence detection parameters (only used when REMOVE_SILENCE=true)
SILENCE_THRESHOLD_DB="${SILENCE_THRESHOLD_DB:--40}"
SILENCE_MIN_DURATION="${SILENCE_MIN_DURATION:-1}"

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

echo "Preparing audio files from categories in: $DATA_DIR/input"
echo "=========================================="
echo ""

# Iterate over all category folders in input directory
find "$DATA_DIR/input" -mindepth 1 -maxdepth 1 -type d | while read -r category_dir; do
    category_name=$(basename "$category_dir")

    echo "Processing category: $category_name"
    echo "---"

    # Create output directory for this category
    mkdir -p "$DATA_DIR/output/$category_name/wav"

    # Counter for skipped files in this category
    skipped_count=0

    # Process all supported media files
    # Find all media files in this category's input directory
    while IFS= read -r -d '' input_file; do

        # Get the base filename and extension
        filename=$(basename "$input_file")
        extension="${filename##*.}"
        base_name="${filename%.*}"

        # Define the output .wav file path
        output_wav="$DATA_DIR/output/$category_name/wav/$base_name.wav"

        # Check if output WAV file already exists
        if [ -f "$output_wav" ]; then
            skipped_count=$((skipped_count + 1))
            if [ "$VERBOSE" = "true" ]; then
                echo "  ⏭️  Skipping: $filename (WAV already exists)"
                echo "  ---"
            fi
        else
            echo "  Processing: $filename"

            if [ "$REMOVE_SILENCE" = "true" ]; then
                # 3-step silence removal process
                temp_wav="/tmp/prepare_audio_temp_${base_name}_$$.wav"
                silence_log="/tmp/prepare_audio_silence_${base_name}_$$.log"

                # Step 1: Convert to WAV and detect silence
                echo "    Converting and detecting silence (using $NUM_THREADS threads)..."
                ffmpeg -threads "$NUM_THREADS" -y -i "$input_file" \
                    -vn -ar 16000 -ac 1 -c:a pcm_s16le \
                    -af "silencedetect=noise=${SILENCE_THRESHOLD_DB}dB:d=${SILENCE_MIN_DURATION}" \
                    -f wav "$temp_wav" \
                    2> "$silence_log" </dev/null
                ffmpeg_exit=$?

                if [ $ffmpeg_exit -ne 0 ]; then
                    echo "    🚨 FAILED to convert $filename"
                    rm -f "$temp_wav" "$silence_log"
                    exit 1
                fi

                # Step 2: Build select expression from silence log
                DURATION=$(ffprobe -v error -show_entries format=duration \
                    -of default=noprint_wrappers=1:nokey=1 "$temp_wav")

                SELECT=$(awk '
                    BEGIN           { prev = 0 }
                    /silence_start/ { split($0, a, "silence_start: "); start = a[2] }
                    /silence_end/   { split($0, a, "silence_end: ");   end = a[2]+0;
                                       if (start+0 > prev+0) printf "between(t,%s,%s)+", prev, start;
                                       prev = end }
                    END             { if (prev+0 < '"$DURATION"'+0) printf "between(t,%s,%s)", prev, '"$DURATION"' }
                ' "$silence_log")

                # Remove trailing '+' if the audio ends with silence
                SELECT="${SELECT%+}"

                # Generate silence_map.json for timestamp reconstruction
                silence_map="$DATA_DIR/output/$category_name/wav/$base_name.silence_map.json"
                uv run python scripts/generate_silence_map.py \
                    "$silence_log" "$DURATION" "$filename" "$silence_map" \
                    --threshold-db "$SILENCE_THRESHOLD_DB" \
                    --min-duration "$SILENCE_MIN_DURATION"

                # Step 3: Extract speech segments only
                if [ -n "$SELECT" ]; then
                    echo "    Extracting speech segments (removing silence)..."
                    ffmpeg -threads "$NUM_THREADS" -y -i "$temp_wav" \
                        -af "aselect='${SELECT}',asetpts=N/SR/TB" \
                        -ar 16000 -ac 1 -c:a pcm_s16le \
                        -loglevel error -stats "$output_wav" </dev/null
                    ffmpeg_exit=$?
                else
                    # No silence detected, use the converted file as-is
                    echo "    No silence detected, keeping full audio..."
                    mv "$temp_wav" "$output_wav"
                    ffmpeg_exit=0
                fi

                rm -f "$temp_wav" "$silence_log"
            else
                # Standard conversion without silence removal
                echo "    Converting to output/$category_name/wav/$base_name.wav (using $NUM_THREADS threads)..."
                ffmpeg -threads "$NUM_THREADS" -y -i "$input_file" -vn -ar 16000 -ac 1 -c:a pcm_s16le -loglevel error -stats "$output_wav" </dev/null
                ffmpeg_exit=$?
            fi

            if [ $ffmpeg_exit -eq 0 ]; then
                echo "    ✅ Done: $base_name.wav"
            else
                echo "    🚨 FAILED to convert $filename"
                exit 1
            fi
            echo "  ---"
        fi

    done < <(find "$category_dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.wav" -o -iname "*.webm" -o -iname "*.m4a" -o -iname "*.mov" -o -iname "*.m4v" -o -iname "*.mp3" -o -iname "*.ogg" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.flv" \) -print0)

    # Print skip summary if any files were skipped
    if [ $skipped_count -gt 0 ]; then
        echo "⏭️  Skipped $skipped_count file(s) (WAV already exists)"
    fi

    echo ""
done

echo "Audio preparation complete."

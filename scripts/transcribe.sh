#!/bin/bash

# --- Configuration ---
# Set this variable to the directory containing your data
# Or pass DATA_DIR as an environment variable
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/path/to/your/data/folder"
fi

# Model name for organizing transcripts (REQUIRED - pass via environment variable)
if [ -z "$MODEL_NAME" ]; then
    echo "🚨 ERROR: MODEL_NAME environment variable is required (e.g., MODEL_NAME=medium-en)"
    exit 1
fi

# HuggingFace model repo (REQUIRED - pass via environment variable)
if [ -z "$MODEL_REPO" ]; then
    echo "🚨 ERROR: MODEL_REPO environment variable is required (e.g., MODEL_REPO=mlx-community/whisper-medium-mlx)"
    exit 1
fi

# VERBOSE: Set to "true" to show individual skip messages, otherwise show summary
# Default is "false" (summary only)
VERBOSE="${VERBOSE:-false}"
# --- End Configuration ---

# Check if DATA_DIR is set to the default value
if [ "$DATA_DIR" == "/path/to/your/data/folder" ]; then
    echo "🚨 ERROR: Please edit this script and set the DATA_DIR variable to your folder."
    exit 1
fi

echo "Starting batch transcription with model: $MODEL_NAME"
echo "Model repo: $MODEL_REPO"
echo "=========================================="
echo ""

# Iterate over all category folders in output directory
find "$DATA_DIR/output" -mindepth 1 -maxdepth 1 -type d | while read -r category_dir; do
    category_name=$(basename "$category_dir")

    echo "Processing category: $category_name"
    echo "---"

    # Create transcripts directory for this category
    mkdir -p "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME"

    # Counter for skipped files in this category
    skipped_count=0

    # Find all .wav files in this category's wav directory
    while IFS= read -r -d '' wav_file; do

        # Get the base filename without the .wav extension
        base_name=$(basename "$wav_file" .wav)

        # Check if transcript already exists
        if [ -f "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME/$base_name.txt" ]; then
            skipped_count=$((skipped_count + 1))
            if [ "$VERBOSE" = "true" ]; then
                echo "  ⏭️  Skipping: $base_name.wav (transcript already exists)"
                echo "  ---"
            fi
            continue
        fi

        echo "  Transcribing: $base_name.wav"

        # Create a temp directory for this transcription
        temp_dir=$(mktemp -d)

        # Transcribe WAV file to temp directory (generate all formats, keep txt + srt)
        uv run mlx_whisper "$wav_file" --model "$MODEL_REPO" --output-dir "$temp_dir" --output-format all

        if [ $? -eq 0 ]; then
            # Move only txt and srt files to the transcripts directory
            moved_files=0
            for ext in txt srt; do
                generated_file=$(find "$temp_dir" -type f -name "*.$ext" | head -n 1)
                if [ -f "$generated_file" ]; then
                    mv "$generated_file" "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME/$base_name.$ext"
                    moved_files=$((moved_files + 1))
                fi
            done

            if [ $moved_files -gt 0 ]; then
                # Remap SRT timestamps if silence was removed (silence_map.json exists)
                silence_map="$DATA_DIR/output/$category_name/wav/$base_name.silence_map.json"
                srt_file="$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME/$base_name.srt"
                if [ -f "$silence_map" ] && [ -f "$srt_file" ]; then
                    echo "    Remapping SRT timestamps to original audio timeline..."
                    uv run python scripts/remap_srt_timestamps.py "$srt_file" "$silence_map"
                fi

                echo "    ✅ Done: $base_name ($moved_files formats)"
            else
                echo "    🚨 FAILED: No transcript generated for $base_name.wav"
                rm -rf "$temp_dir"
                exit 1
            fi
        else
            echo "    🚨 FAILED to transcribe $base_name.wav"
            rm -rf "$temp_dir"
            exit 1
        fi

        # Clean up temp directory
        rm -rf "$temp_dir"

        echo "  ---"
    done < <(find "$category_dir/wav" -maxdepth 1 -type f -name "*.wav" -print0 2>/dev/null)

    # Print skip summary if any files were skipped
    if [ $skipped_count -gt 0 ]; then
        echo "⏭️  Skipped $skipped_count file(s) (transcript already exists)"
    fi

    echo ""
done

echo "Batch transcription complete."

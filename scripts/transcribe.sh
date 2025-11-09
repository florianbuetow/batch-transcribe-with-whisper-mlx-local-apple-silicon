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

    # Find all .wav files in this category's wav directory
    find "$category_dir/wav" -maxdepth 1 -type f -name "*.wav" -print0 2>/dev/null | while IFS= read -r -d '' wav_file; do

        # Get the base filename without the .wav extension
        base_name=$(basename "$wav_file" .wav)

        # Check if transcript already exists
        # Note: mlx_whisper creates transcripts by removing .wav and changing extension to .txt
        # It strips file extensions (e.g., "video.ai.wav" becomes "video.txt")
        # But keeps trailing dots (e.g., "video..wav" becomes "video..txt")
        base_name_no_ext="${base_name%%.*}"  # Remove everything after first dot (handles .ai case)

        # Check both cases: with and without the trailing dot
        if [ -f "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME/$base_name.txt" ] || \
           [ -f "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME/$base_name_no_ext.txt" ]; then
            echo "  ⏭️  Skipping: $base_name.wav (transcript already exists)"
            echo "  ---"
            continue
        fi

        echo "  Transcribing: $base_name.wav"

        # Transcribe WAV file
        uv run mlx_whisper "$wav_file" --model "$MODEL_REPO" --output-dir "$DATA_DIR/output/$category_name/transcripts/$MODEL_NAME"

        if [ $? -eq 0 ]; then
            echo "    ✅ Done: $base_name"
        else
            echo "    🚨 FAILED to transcribe $base_name.wav"
            exit 1
        fi

        echo "  ---"
    done

    echo ""
done

echo "Batch transcription complete."

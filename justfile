# Batch Transcribe Audio Files using MLX Whisper on Apple Silicon

# Supported input file formats for conversion
audio_video_formats := "mp4 mp3 m4a wav avi mkv webm flv mov"

# Default recipe: show help
default:
    @just help

# Show available targets
help:
    @echo ""
    @echo "Available targets:"
    @echo "  init       - Install dependencies"
    @echo "  prepare    - Convert audio/video files to WAV files"
    @echo "  tiny       - Transcribe WAVs with tiny model (fastest, multilingual)"
    @echo "  tiny-en    - Transcribe WAVs with tiny English-only model"
    @echo "  medium     - Transcribe WAVs with medium model (multilingual)"
    @echo "  medium-en  - Transcribe WAVs with medium English-only model"
    @echo "  large      - Transcribe WAVs with large-v3 model (best quality, multilingual)"
    @echo "  status     - Show transcription progress for each category"
    @echo "  clean      - Remove all WAV and transcript files"
    @echo ""

# Install dependencies
init:
    @echo ""
    uv sync
    @echo ""

# Convert audio/video files to WAV format
prepare VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" VERBOSE="{{VERBOSE}}" bash scripts/prepare_audio.sh
    @echo ""

# Transcribe with tiny model (fastest, multilingual)
tiny VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=tiny MODEL_REPO=mlx-community/whisper-tiny VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""

# Transcribe with tiny English-only model
tiny-en VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=tiny-en MODEL_REPO=mlx-community/whisper-tiny VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""

# Transcribe with medium model (balanced, multilingual)
medium VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=medium MODEL_REPO=mlx-community/whisper-medium-mlx VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""

# Transcribe with medium English-only model
medium-en VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=medium-en MODEL_REPO=mlx-community/whisper-medium-mlx VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""

# Transcribe with large model (best quality, multilingual)
large VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=large MODEL_REPO=mlx-community/whisper-large-v3-mlx VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""

# Show transcription progress for each category
status:
    #!/usr/bin/env bash
    echo ""
    echo "Transcription Progress by Model and Category"
    echo "============================================="
    echo ""
    tmpfile=$(mktemp)
    models="tiny tiny-en medium medium-en large"
    formats="{{audio_video_formats}}"
    for category in data/input/*/; do
        category_name=$(basename "$category")
        if [ "$category_name" = "*" ]; then continue; fi
        find_expr=""
        first=true
        for fmt in $formats; do
            if [ "$first" = true ]; then
                find_expr="-iname \"*.$fmt\""
                first=false
            else
                find_expr="$find_expr -o -iname \"*.$fmt\""
            fi
        done
        input_count=$(eval "find \"$category\" -type f \( $find_expr \) 2>/dev/null | wc -l | tr -d ' '")
        wav_count=0
        if [ -d "data/output/$category_name/wav" ]; then
            wav_count=$(find "data/output/$category_name/wav" -type f -name "*.wav" 2>/dev/null | wc -l | tr -d ' ')
        fi
        total_progress=0
        model_count=0
        model_data=""
        for model in $models; do
            if [ -d "data/output/$category_name/transcripts/$model" ]; then
                transcript_count=$(find "data/output/$category_name/transcripts/$model" -type f -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
                if [ $input_count -gt 0 ]; then
                    progress=$((transcript_count * 100 / input_count))
                else
                    progress=0
                fi
                total_progress=$((total_progress + progress))
                model_count=$((model_count + 1))
                model_data="$model_data$model:$transcript_count:$progress|"
            fi
        done
        if [ $model_count -gt 0 ]; then
            avg_progress=$((total_progress / model_count))
        else
            avg_progress=0
        fi
        printf "%03d|%s|%d|%d|%s\n" $avg_progress "$category_name" $input_count $wav_count "$model_data" >> "$tmpfile"
    done
    sort -t'|' -k1 -nr "$tmpfile" | while IFS='|' read avg_progress category_name input_count wav_count model_data; do
        echo "Category: $category_name"
        printf "  Input files: %3d\n" $input_count
        printf "  WAV files:   %3d\n" $wav_count
        echo ""
        echo "$model_data" | tr '|' '\n' | while IFS=':' read model transcript_count progress; do
            if [ -n "$model" ]; then
                printf "  %-10s: %3d transcripts (%3d%%)\n" "$model" $transcript_count $progress
            fi
        done
        echo ""
    done
    rm -f "$tmpfile"
    echo ""

# Remove all WAV and transcript files
clean:
    @echo ""
    @echo "Removing WAV and transcript files..."
    rm -rf data/output/*/wav/*
    rm -rf data/output/*/transcripts/*
    @echo "Clean complete"
    @echo ""

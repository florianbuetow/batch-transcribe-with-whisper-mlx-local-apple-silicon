# =============================================================================
# Justfile Rules (follow these when editing justfile):
#
# 1. Use printf (not echo) to print colors — some terminals won't render
#    colors with echo.
#
# 2. Always add an empty `@echo ""` line before and after each target's
#    command block.
#
# 3. Always add new targets to the help section and update it when targets
#    are added, modified or removed.
#
# 4. Target ordering in help (and in this file) matters:
#    - Setup targets first (init, clean, help, etc.)
#    - Preparation and pipeline targets next
#    - Transcription model targets next
#    - Post-processing targets next
#    - Status, testing, and CI targets last
#    Group related targets together and separate groups with an empty
#    `@echo ""` line in the help output.
#
# 5. Composite targets that call multiple sub-targets must fail fast:
#    exit 1 on the first error. Never skip over errors or warnings.
#    Use `set -e` or `&&` chaining to ensure immediate abort with the
#    appropriate error message.
#
# 6. Every target must end with a clear short status message:
#    - On success: green (\033[32m) message confirming completion.
#      E.g. printf "\033[32m✓ init completed successfully\033[0m\n"
#    - On failure: red (\033[31m) message indicating what failed, then exit 1.
#      E.g. printf "\033[31m✗ transcribe failed\033[0m\n"
#
# 7. Targets must be shown in groups separated by empty newlines in the
#    help section.
# =============================================================================


# Supported input file formats for conversion
audio_video_formats := "mp4 mp3 m4a wav avi mkv webm flv mov"

# Default recipe: show available commands
_default:
    @just help

# Show help information
help:
    @echo ""
    @clear
    @echo ""
    @printf "\033[0;34m=== batch-transcribe-with-whisper-mlx ===\033[0m\n"
    @echo ""
    @printf "\033[0;33mSetup & Lifecycle:\033[0m\n"
    @printf "  %-38s %s\n" "init" "Install dependencies"
    @printf "  %-38s %s\n" "clean" "Remove all WAV, transcript, and silence map files"
    @printf "  %-38s %s\n" "help" "Show this help information"
    @echo ""
    @printf "\033[0;33mEntire Pipeline:\033[0m\n"
    @printf "  %-38s %s\n" "go" "Alias for medium-en-all"
    @printf "  %-38s %s\n" "tiny-all" "Run full pipeline: prepare → tiny → clean-transcripts"
    @printf "  %-38s %s\n" "tiny-en-all" "Run full pipeline: prepare → tiny-en → clean-transcripts"
    @printf "  %-38s %s\n" "medium-all" "Run full pipeline: prepare → medium → clean-transcripts"
    @printf "  %-38s %s\n" "medium-en-all" "Run full pipeline: prepare → medium-en → clean-transcripts"
    @printf "  %-38s %s\n" "large-all" "Run full pipeline: prepare → large → clean-transcripts"
    @echo ""
    @printf "\033[0;33mPreparation:\033[0m\n"
    @printf "  %-38s %s\n" "download URL" "Download audio from URL into data/input/youtube/"
    @printf "  %-38s %s\n" "prepare" "Convert media to WAV (with silence removal + silence map)"
    @echo ""
    @printf "\033[0;33mTranscription Models:\033[0m\n"
    @printf "  %-38s %s\n" "tiny" "Transcribe WAVs with tiny model (fastest, multilingual)"
    @printf "  %-38s %s\n" "tiny-en" "Transcribe WAVs with tiny English-only model"
    @printf "  %-38s %s\n" "medium" "Transcribe WAVs with medium model (multilingual)"
    @printf "  %-38s %s\n" "medium-en" "Transcribe WAVs with medium English-only model"
    @printf "  %-38s %s\n" "large" "Transcribe WAVs with large-v3 model (best quality, multilingual)"
    @echo ""
    @printf "\033[0;33mPost-processing:\033[0m\n"
    @printf "  %-38s %s\n" "clean-transcripts" "Remove hallucinations from transcripts"
    @echo ""
    @printf "\033[0;33mStatus & Testing:\033[0m\n"
    @printf "  %-38s %s\n" "status" "Show transcription progress for each category"
    @printf "  %-38s %s\n" "test" "Run end-to-end pipeline test"
    @echo ""

# Initialize the development environment
init:
    @echo ""
    uv sync
    @echo ""
    @printf "\033[32m✓ init completed successfully\033[0m\n"
    @echo ""

# Alias for medium-en-all
go VERBOSE="" REMOVE_SILENCE="true":
    @just medium-en-all VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}"

# Run full pipeline: prepare → tiny transcription → clean hallucinations
tiny-all VERBOSE="" REMOVE_SILENCE="true":
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "Running full tiny pipeline...\n"
    echo ""

    just prepare VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}" || {
        printf "\033[31m✗ tiny-all failed: prepare step exited with errors\033[0m\n"
        exit 1
    }

    just tiny VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ tiny-all failed: tiny transcription exited with errors\033[0m\n"
        exit 1
    }

    just clean-transcripts MODEL="tiny" VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ tiny-all failed: clean-transcripts exited with errors\033[0m\n"
        exit 1
    }

    echo ""
    printf "\033[32m✓ tiny-all pipeline completed successfully\033[0m\n"
    echo ""

# Run full pipeline: prepare → tiny-en transcription → clean hallucinations
tiny-en-all VERBOSE="" REMOVE_SILENCE="true":
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "Running full tiny-en pipeline...\n"
    echo ""

    just prepare VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}" || {
        printf "\033[31m✗ tiny-en-all failed: prepare step exited with errors\033[0m\n"
        exit 1
    }

    just tiny-en VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ tiny-en-all failed: tiny-en transcription exited with errors\033[0m\n"
        exit 1
    }

    just clean-transcripts MODEL="tiny-en" VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ tiny-en-all failed: clean-transcripts exited with errors\033[0m\n"
        exit 1
    }

    echo ""
    printf "\033[32m✓ tiny-en-all pipeline completed successfully\033[0m\n"
    echo ""

# Run full pipeline: prepare → medium transcription → clean hallucinations
medium-all VERBOSE="" REMOVE_SILENCE="true":
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "Running full medium pipeline...\n"
    echo ""

    just prepare VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}" || {
        printf "\033[31m✗ medium-all failed: prepare step exited with errors\033[0m\n"
        exit 1
    }

    just medium VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ medium-all failed: medium transcription exited with errors\033[0m\n"
        exit 1
    }

    just clean-transcripts MODEL="medium" VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ medium-all failed: clean-transcripts exited with errors\033[0m\n"
        exit 1
    }

    echo ""
    printf "\033[32m✓ medium-all pipeline completed successfully\033[0m\n"
    echo ""

# Run full pipeline: prepare → medium-en transcription → clean hallucinations
medium-en-all VERBOSE="" REMOVE_SILENCE="true":
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "Running full medium-en pipeline...\n"
    echo ""

    just prepare VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}" || {
        printf "\033[31m✗ medium-en-all failed: prepare step exited with errors\033[0m\n"
        exit 1
    }

    just medium-en VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ medium-en-all failed: medium-en transcription exited with errors\033[0m\n"
        exit 1
    }

    just clean-transcripts MODEL="medium-en" VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ medium-en-all failed: clean-transcripts exited with errors\033[0m\n"
        exit 1
    }

    echo ""
    printf "\033[32m✓ medium-en-all pipeline completed successfully\033[0m\n"
    echo ""

# Run full pipeline: prepare → large transcription → clean hallucinations
large-all VERBOSE="" REMOVE_SILENCE="true":
    #!/usr/bin/env bash
    set -e
    echo ""
    printf "Running full large pipeline...\n"
    echo ""

    just prepare VERBOSE="{{VERBOSE}}" REMOVE_SILENCE="{{REMOVE_SILENCE}}" || {
        printf "\033[31m✗ large-all failed: prepare step exited with errors\033[0m\n"
        exit 1
    }

    just large VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ large-all failed: large transcription exited with errors\033[0m\n"
        exit 1
    }

    just clean-transcripts MODEL="large" VERBOSE="{{VERBOSE}}" || {
        printf "\033[31m✗ large-all failed: clean-transcripts exited with errors\033[0m\n"
        exit 1
    }

    echo ""
    printf "\033[32m✓ large-all pipeline completed successfully\033[0m\n"
    echo ""

# Download audio from a URL into data/input/youtube/
download URL:
    @echo ""
    mkdir -p {{justfile_directory()}}/data/input/youtube
    yt-dlp -f "bestaudio[ext=m4a]" -o "{{justfile_directory()}}/data/input/youtube/%(title)s.%(ext)s" "{{URL}}"
    @echo ""
    @printf "\033[32m✓ download completed successfully\033[0m\n"
    @echo ""

# Convert audio/video files to WAV format (silence removal enabled by default)
prepare VERBOSE="" REMOVE_SILENCE="true":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" REMOVE_SILENCE="{{REMOVE_SILENCE}}" VERBOSE="{{VERBOSE}}" bash scripts/prepare_audio.sh
    @echo ""
    @printf "\033[32m✓ prepare completed successfully\033[0m\n"
    @echo ""

# Transcribe with tiny model (fastest, multilingual)
tiny VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=tiny MODEL_REPO=mlx-community/whisper-tiny VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""
    @printf "\033[32m✓ tiny transcription completed successfully\033[0m\n"
    @echo ""

# Transcribe with tiny English-only model
tiny-en VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=tiny-en MODEL_REPO=mlx-community/whisper-tiny LANGUAGE=en VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""
    @printf "\033[32m✓ tiny-en transcription completed successfully\033[0m\n"
    @echo ""

# Transcribe with medium model (balanced, multilingual)
medium VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=medium MODEL_REPO=mlx-community/whisper-medium-mlx VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""
    @printf "\033[32m✓ medium transcription completed successfully\033[0m\n"
    @echo ""

# Transcribe with medium English-only model
medium-en VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=medium-en MODEL_REPO=mlx-community/whisper-medium-mlx LANGUAGE=en VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""
    @printf "\033[32m✓ medium-en transcription completed successfully\033[0m\n"
    @echo ""

# Transcribe with large model (best quality, multilingual)
large VERBOSE="":
    @echo ""
    DATA_DIR="{{justfile_directory()}}/data" MODEL_NAME=large MODEL_REPO=mlx-community/whisper-large-v3-mlx VERBOSE="{{VERBOSE}}" bash scripts/transcribe.sh
    @echo ""
    @printf "\033[32m✓ large transcription completed successfully\033[0m\n"
    @echo ""

# Clean transcripts by removing hallucinations (repetitive patterns)
clean-transcripts MODEL="" VERBOSE="":
    @echo ""
    @printf "Cleaning transcripts (removing hallucinations)...\n"
    DATA_DIR="{{justfile_directory()}}/data" MODEL="{{MODEL}}" VERBOSE="{{VERBOSE}}" uv run python scripts/clean_transcripts.py
    @echo ""
    @printf "\033[32m✓ clean-transcripts completed successfully\033[0m\n"
    @echo ""

# Show transcription progress for each category
status:
    #!/usr/bin/env bash
    echo ""
    printf "\033[0;34mTranscription Progress by Model and Category\033[0m\n"
    printf "\033[0;34m=============================================\033[0m\n"
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
        printf "\033[0;33mCategory: %s\033[0m\n" "$category_name"
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
    printf "\033[32m✓ status completed successfully\033[0m\n"
    echo ""

# Run end-to-end pipeline test (prepare → transcribe → clean-transcripts)
test:
    @echo ""
    @bash tests/test_e2e.sh
    @echo ""
    @printf "\033[32m✓ test completed successfully\033[0m\n"
    @echo ""

# Remove all WAV, transcript, silence map, and cleaned transcript files
clean:
    @echo ""
    @printf "Removing WAV, transcript, and silence map files...\n"
    rm -rf data/output/*/wav/*
    rm -rf data/output/*/transcripts/*
    rm -rf data/output/*/transcripts_cleaned/*
    @echo ""
    @printf "\033[32m✓ clean completed successfully\033[0m\n"
    @echo ""

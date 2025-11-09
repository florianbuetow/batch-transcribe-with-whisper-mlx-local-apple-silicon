#!/bin/bash

# --- Configuration ---
# Set this variable to the directory containing your data folders
# Or pass DATA_DIR as an environment variable
if [ -z "$DATA_DIR" ]; then
    DATA_DIR="/path/to/your/data/folder"
fi
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

    # Process all supported media files (.mp4, .wav, .webm, .m4a, .mov, .m4v, .mp3, .ogg)
    # Find all media files in this category's input directory
    find "$category_dir" -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.wav" -o -name "*.webm" -o -name "*.m4a" -o -name "*.mov" -o -name "*.m4v" -o -name "*.mp3" -o -name "*.ogg" \) -print0 | while IFS= read -r -d '' input_file; do

        # Get the base filename and extension
        filename=$(basename "$input_file")
        extension="${filename##*.}"
        base_name="${filename%.*}"

        # Define the output .wav file path
        output_wav="$DATA_DIR/output/$category_name/wav/$base_name.wav"

        # Check if output WAV file already exists
        if [ -f "$output_wav" ]; then
            echo "  ⏭️  Skipping: $filename (WAV already exists)"
        else
            echo "  Processing: $filename"

            # Convert to WAV with proper format
            # -threads: Number of threads to use
            # -y: Overwrite output file without asking
            # -i: Input file
            # -vn: No video (discard video stream)
            # -ar 16000: Audio rate 16kHz
            # -ac 1: Audio channels 1 (mono)
            # -c:a pcm_s16le: Codec for 16-bit PCM WAV
            # -loglevel error: Only show errors
            # -stats: Show brief progress
            echo "    Converting to output/$category_name/wav/$base_name.wav (using $NUM_THREADS threads)..."
            ffmpeg -threads "$NUM_THREADS" -y -i "$input_file" -vn -ar 16000 -ac 1 -c:a pcm_s16le -loglevel error -stats "$output_wav" </dev/null
            ffmpeg_exit=$?

            if [ $ffmpeg_exit -eq 0 ]; then
                echo "    ✅ Done: $base_name.wav"
            else
                echo "    🚨 FAILED to convert $filename"
                exit 1
            fi
        fi

        echo "  ---"
    done

    echo ""
done

echo "Audio preparation complete."

# Batch Transcribe Audio Files using MLX Whisper on Apple Silicon

This project uses [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper), Apple's MLX framework implementation of OpenAI's Whisper model, to transcribe audio and video files on Apple Silicon (M1/M2/M3) Macs. It is optimized for high-performance local inference on Mac hardware and requires no GPU or cloud services.

Audio and video files are organized into category folders (e.g., by source, channel, or topic), and the transcription workflow handles audio conversion, batch processing, and output management automatically.

---

## Project Structure

```bash
.
├── Makefile
├── README.md
├── pyproject.toml
├── scripts/
│   ├── prepare_audio.sh
│   └── transcribe.sh
└── data/
    ├── input/              # Source media files organized by category
    │   ├── category1/
    │   ├── category2/
    │   └── ...
    └── output/             # Generated files organized by category
        ├── category1/
        │   ├── wav/        # Converted audio files
        │   └── transcripts/
        │       ├── tiny/
        │       ├── medium/
        │       └── large/
        └── ...
```

- `Makefile`: Automation targets for dependency setup, audio preparation, and transcription with different models.
- `pyproject.toml`: Python project configuration with MLX Whisper dependency.
- `scripts/prepare_audio.sh`: Converts media files to WAV format (16kHz, mono, 16-bit PCM).
- `scripts/transcribe.sh`: Batch transcribes WAV files using MLX Whisper models.
- `data/input/`: Place your media files here, organized into category subfolders.
- `data/output/`: Generated WAV files and transcripts are stored here, organized by category and model.

---

## Whisper Models Available

Models are automatically downloaded from HuggingFace when first used. Choose the model that best fits your needs:

| Model | Speed | Language Support | Quality | HuggingFace Repo |
|-------|-------|------------------|---------|------------------|
| **tiny** | Fastest | Multilingual | Basic | mlx-community/whisper-tiny |
| **tiny-en** | Fastest | English only | Basic | mlx-community/whisper-tiny |
| **medium** | Balanced | Multilingual | Good | mlx-community/whisper-medium-mlx |
| **medium-en** | Balanced | English only | Good | mlx-community/whisper-medium-mlx |
| **large** | Slowest | Multilingual | Best | mlx-community/whisper-large-v3-mlx |

---

## Prerequisites

- **macOS with Apple Silicon** (M1, M2, M3, or later)
- **UV package manager** ([installation instructions](https://docs.astral.sh/uv/getting-started/installation/))
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
- **FFmpeg** for audio conversion:
  ```bash
  brew install ffmpeg
  ```

---

## Usage

### 1. Install Dependencies

First, install the required Python dependencies:

```bash
make init
```

This runs `uv sync` to set up the Python environment with MLX Whisper.

### 2. Add Media Files

Organize your media files into category folders inside `data/input/`:

```bash
mkdir -p data/input/my-podcasts
cp /path/to/episode1.mp4 data/input/my-podcasts/
cp /path/to/episode2.m4a data/input/my-podcasts/
```

Supported formats: `.mp4`, `.wav`, `.webm`, `.m4a`, `.mov`, `.m4v`, `.mp3`, `.ogg`

### 3. Prepare Audio Files

Convert all media files to WAV format (required by Whisper):

```bash
make prepare
```

This will:
- Scan all category folders in `data/input/`
- Convert media files to 16kHz mono WAV format
- Save converted files to `data/output/[category]/wav/`
- Skip files that are already converted (idempotent)
- Use multi-threaded FFmpeg for optimal performance

### 4. Transcribe with Your Chosen Model

Run transcription with one of the available models:

```bash
make tiny       # Fastest, multilingual
make tiny-en    # Fastest, English-only
make medium     # Balanced, multilingual
make medium-en  # Balanced, English-only
make large      # Best quality, multilingual
```

This will:
- Process all WAV files in `data/output/*/wav/`
- Download the model from HuggingFace if not cached
- Transcribe each file using MLX Whisper
- Save transcripts to `data/output/[category]/transcripts/[model]/`
- Skip files that are already transcribed (idempotent)

### 5. View Transcripts

After transcription, you will find your transcripts organized by category and model:

```bash
data/output/my-podcasts/transcripts/medium/episode1.txt
data/output/my-podcasts/transcripts/medium/episode2.txt
```

---

## Example Workflow

```bash
# Install dependencies
make init

# Add your media files
mkdir -p data/input/interviews
cp interview1.mp4 data/input/interviews/
cp interview2.m4a data/input/interviews/

# Convert to WAV
make prepare

# Transcribe with medium model (good balance of speed and quality)
make medium

# View results
cat data/output/interviews/transcripts/medium/interview1.txt
```

---

## Advanced Usage

### Running Multiple Models

You can transcribe the same files with different models to compare quality:

```bash
make prepare    # Convert once
make tiny       # Fast preview
make medium     # Better quality
make large      # Best quality
```

Each model's output is stored separately in `data/output/[category]/transcripts/[model]/`.

### Processing Multiple Categories

Simply add folders to `data/input/` and the scripts will process them all:

```bash
data/input/
├── podcasts/
├── interviews/
├── lectures/
└── meetings/
```

Running `make prepare` and `make medium` will process all categories.

### Clean Up

To remove all generated WAV files and transcripts (keeps original input files):

```bash
make clean
```

---

## Performance Notes

- **MLX Optimization**: MLX is specifically optimized for Apple Silicon, providing excellent performance without requiring external GPUs.
- **Multi-threading**: Audio conversion uses all available CPU cores automatically.
- **Model Caching**: Models are downloaded once and cached locally in `~/.cache/huggingface/`.
- **Idempotent Operations**: Scripts skip already-processed files, making it safe to re-run commands.
- **Memory Usage**: Larger models require more RAM. The `large` model may need 16GB+ RAM for long audio files.

---

## Troubleshooting

### No transcripts generated?

- Check that WAV files exist in `data/output/[category]/wav/`
- Verify `make prepare` completed successfully
- Ensure you have enough disk space and RAM

### Audio conversion failed?

- Verify FFmpeg is installed: `ffmpeg -version`
- Check that input files are valid media files
- Look for error messages during `make prepare`

### Model download failed?

- Check your internet connection
- Verify you have enough disk space (~1-3GB per model)
- Models are cached in `~/.cache/huggingface/hub/`

### "UV not found" error?

Install UV package manager:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Transcription is too slow?

- Use a smaller model (`tiny` or `medium` instead of `large`)
- Process shorter audio segments
- Ensure no other intensive tasks are running

---

## File Organization Tips

Recommended category naming conventions:

```bash
data/input/
├── @ChannelName/          # YouTube channels
├── ProjectName/            # Project recordings
├── 2024-Q1-Meetings/      # Time-based organization
└── InterviewSeries/        # Content series
```

This keeps transcripts well-organized in `data/output/` with the same structure.

---

## Notes

- **Privacy-focused**: All processing happens locally on your Mac. No cloud services or API calls (except for model downloads).
- **Category-based organization**: Unlike model-based routing, this system organizes by content source/category.
- **Two-stage workflow**: Separate audio preparation and transcription allows you to prepare once, then try different models.
- **Output format**: Generates `.txt` transcripts by default. MLX Whisper also supports other formats.
- **Apple Silicon only**: This project requires Apple Silicon (M1/M2/M3). For Intel Macs or other platforms, use [whisper.cpp](https://github.com/ggerganov/whisper.cpp) instead.

---

## Related Projects

- For GPU-accelerated transcription on NVIDIA GPUs: [batch-transcribe-with-whisper-local-gpu](https://github.com/florianbuetow/batch-transcribe-with-whisper-local-gpu)
- For CPU-based Docker transcription: [batch-transcribe-with-whispercpp-local-cpu](https://github.com/florianbuetow/batch-transcribe-with-whispercpp-local-cpu)

---

## License

This project structure and scripts are provided as-is for batch transcription workflows using MLX Whisper on Apple Silicon.

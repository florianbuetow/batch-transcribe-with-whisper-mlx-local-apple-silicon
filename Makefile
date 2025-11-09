.PHONY: help init prepare tiny tiny-en medium medium-en large clean

help:
	@echo "Available targets:"
	@echo "  init       - Install dependencies"
	@echo "  prepare    - Convert MP4s to WAV files"
	@echo "  tiny       - Transcribe WAVs with tiny model (fastest, multilingual)"
	@echo "  tiny-en    - Transcribe WAVs with tiny English-only model"
	@echo "  medium     - Transcribe WAVs with medium model (multilingual)"
	@echo "  medium-en  - Transcribe WAVs with medium English-only model"
	@echo "  large      - Transcribe WAVs with large-v3 model (best quality, multilingual)"
	@echo "  clean      - Remove all WAV and transcript files"

init:
	uv sync

prepare:
	DATA_DIR="$(CURDIR)/data" bash scripts/prepare_audio.sh

tiny:
	DATA_DIR="$(CURDIR)/data" MODEL_NAME=tiny MODEL_REPO=mlx-community/whisper-tiny bash scripts/transcribe.sh

tiny-en:
	DATA_DIR="$(CURDIR)/data" MODEL_NAME=tiny-en MODEL_REPO=mlx-community/whisper-tiny bash scripts/transcribe.sh

medium:
	DATA_DIR="$(CURDIR)/data" MODEL_NAME=medium MODEL_REPO=mlx-community/whisper-medium-mlx bash scripts/transcribe.sh

medium-en:
	DATA_DIR="$(CURDIR)/data" MODEL_NAME=medium-en MODEL_REPO=mlx-community/whisper-medium-mlx bash scripts/transcribe.sh

large:
	DATA_DIR="$(CURDIR)/data" MODEL_NAME=large MODEL_REPO=mlx-community/whisper-large-v3-mlx bash scripts/transcribe.sh

clean:
	@echo "Removing WAV and transcript files..."
	rm -rf data/output/*/wav/*
	rm -rf data/output/*/transcripts/*
	@echo "✅ Clean complete"

# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## 2026-05-17

### Added

- `download` command to fetch audio from any URL directly as m4a (no re-encoding).
- `go` shortcut alias for the medium-en full pipeline.

## 2026-03-28

### Added

- Single-command pipeline targets (tiny-all, medium-all, large-all, and -en variants) running prepare → transcribe → clean end-to-end.

### Changed

- Silence removal now uses segment-and-concatenate instead of aselect for more reliable results.
- Colored terminal output and inline justfile conventions documentation added.

## 2026-02-16

### Changed

- Unified dual-pipeline into a single workflow with silence removal and timestamp reconstruction.
- English-only model variants (tiny-en, medium-en) now enforce language to prevent multilingual output.

## 2026-02-06

### Added

- `clean-transcripts` command to automatically remove repetitive hallucination patterns from transcripts.
- Support for mkv, avi, and flv input formats alongside existing mp4, m4a, and wav.
- SRT subtitle file parsing for transcript post-processing.

### Changed

- Replaced Makefile with justfile for all task management.

## 2025-11-09

### Added

- Initial batch transcription pipeline using Whisper MLX on Apple Silicon.
- `status` command showing per-model transcription progress broken down by category.

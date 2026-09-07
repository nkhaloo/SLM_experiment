#!/usr/bin/env python3
"""Transcribe the prerecorded system responses with local Whisper ASR.

Example:
    .venv-asr/bin/python src/transcribe_system_responses.py
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import whisper


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AUDIO_DIR = PROJECT_ROOT / "experiment" / "prerecorded"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "transcripts" / "system_responses"

# Corrections are restricted to unambiguous named entities in the source prompts
# and medication terminology. Both raw and reviewed ASR text are retained.
TRANSCRIPT_CORRECTIONS = {
    "medication_advice": {
        "topomax": "Topamax",
        "tylenol": "Tylenol",
    },
    "medication_fact": {
        "levoquine": "Levaquin",
    },
    "medication_risk": {
        "Corguard": "Corgard",
        "Natalol": "nadolol",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio-dir", type=Path, default=DEFAULT_AUDIO_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--model",
        default="small.en",
        help="Whisper model name (default: small.en).",
    )
    parser.add_argument(
        "--include-practice",
        action="store_true",
        help="Also transcribe practice.mp3.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    audio_dir = args.audio_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    audio_files = sorted(audio_dir.glob("*.mp3"))
    if not args.include_practice:
        audio_files = [path for path in audio_files if path.stem != "practice"]
    if not audio_files:
        raise SystemExit(f"No MP3 files found in {audio_dir}")

    model = whisper.load_model(args.model)
    records: list[dict[str, str]] = []

    for index, audio_path in enumerate(audio_files, start=1):
        print(f"[{index}/{len(audio_files)}] Transcribing {audio_path.name}", flush=True)
        result = model.transcribe(
            str(audio_path),
            language="en",
            task="transcribe",
            fp16=False,
            temperature=0,
            condition_on_previous_text=False,
        )
        raw_transcript = " ".join(result["text"].strip().split())
        transcript = raw_transcript
        for original, correction in TRANSCRIPT_CORRECTIONS.get(audio_path.stem, {}).items():
            transcript = transcript.replace(original, correction)
        record = {
            "id": audio_path.stem,
            "audio_file": str(audio_path.relative_to(PROJECT_ROOT)),
            "raw_asr_transcript": raw_transcript,
            "transcript": transcript,
            "asr_model": args.model,
        }
        records.append(record)
        (output_dir / f"{audio_path.stem}.txt").write_text(
            transcript + "\n", encoding="utf-8"
        )

    (output_dir / "transcripts.json").write_text(
        json.dumps(records, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    with (output_dir / "transcripts.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=records[0].keys())
        writer.writeheader()
        writer.writerows(records)

    print(f"Wrote {len(records)} transcripts to {output_dir}")


if __name__ == "__main__":
    main()

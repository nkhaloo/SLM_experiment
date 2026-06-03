#!/usr/bin/env python3
"""
Download and organize all participant audio recordings from the experiment CSV.

Run with:
    conda run -n SLM python src/download_audio.py

Output structure:
  audio/passage/  — passage_reading files
  audio/trials/   — trial participant recordings and model responses

Naming convention:
  {voice_condition}_user{N}_{type}.wav

  N is a sequential user number (1-based, order from CSV). Type is one of:
    passage, practice_participant, practice_model_response,
    trial{XX}_participant, trial{XX}_model_response
"""

import csv
import os
import subprocess
import sys
import tempfile
import urllib.parse

import requests
from tqdm import tqdm

CSV_PATH = os.path.join(os.path.dirname(__file__), "../experiment_results/participants_results_filtered.csv")
AUDIO_DIR = os.path.join(os.path.dirname(__file__), "../audio")

PASSAGE_DIR = os.path.join(AUDIO_DIR, "passage")
TRIALS_PARTICIPANT_DIR = os.path.join(AUDIO_DIR, "trials", "participant")
TRIALS_MODEL_DIR = os.path.join(AUDIO_DIR, "trials", "model_response")

MAX_WORKERS = 8  # parallel downloads


def get_extension(url: str) -> str:
    path = urllib.parse.urlparse(url).path
    decoded = urllib.parse.unquote(path.split("/o/")[-1])
    if "." in decoded:
        return "." + decoded.rsplit(".", 1)[-1]
    return ".webm"


def convert_to_wav(src: str, dest: str) -> None:
    # Omit -ar and -ac so ffmpeg keeps the source sample rate and channel count unchanged.
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-acodec", "pcm_s16le", dest],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def download_and_convert(url: str, dest_wav: str) -> bool:
    """Download url, convert to wav. Returns True on success, False on error/skip."""
    if not url:
        return False
    if os.path.exists(dest_wav):
        return True  # already done

    ext = get_extension(url)
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp_path = tmp.name

    try:
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        with open(tmp_path, "wb") as f:
            f.write(response.content)
        convert_to_wav(tmp_path, dest_wav)
        return True
    except Exception as exc:
        print(f"\n  ERROR {os.path.basename(dest_wav)}: {exc}", file=sys.stderr)
        if os.path.exists(dest_wav):
            os.remove(dest_wav)  # remove partial file
        return False
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def build_tasks(rows: list[dict]) -> list[tuple[str, str]]:
    """Return list of (url, dest_wav_path) for every audio field in the CSV."""
    tasks = []

    for user_n, row in enumerate(rows, start=1):
        condition = row["voice_condition"].strip()
        prefix = f"{condition}_user{user_n}"

        # Passage reading
        url = row.get("passage_reading", "").strip()
        if url:
            tasks.append((url, os.path.join(PASSAGE_DIR, f"{prefix}_passage.wav")))

        # Practice recordings
        url = row.get("practice_participant_recording", "").strip()
        if url:
            tasks.append((url, os.path.join(TRIALS_PARTICIPANT_DIR, f"{prefix}_practice_participant.wav")))

        url = row.get("practice_model_response", "").strip()
        if url:
            tasks.append((url, os.path.join(TRIALS_MODEL_DIR, f"{prefix}_practice_model_response.wav")))

        # Trial recordings (01–20)
        for trial_n in range(1, 21):
            tag = f"trial_{trial_n:02d}"

            url = row.get(f"{tag}_participant_recording", "").strip()
            if url:
                tasks.append((url, os.path.join(TRIALS_PARTICIPANT_DIR, f"{prefix}_{tag}_participant.wav")))

            url = row.get(f"{tag}_model_response", "").strip()
            if url:
                tasks.append((url, os.path.join(TRIALS_MODEL_DIR, f"{prefix}_{tag}_model_response.wav")))

    return tasks


def main() -> None:
    os.makedirs(PASSAGE_DIR, exist_ok=True)
    os.makedirs(TRIALS_PARTICIPANT_DIR, exist_ok=True)
    os.makedirs(TRIALS_MODEL_DIR, exist_ok=True)

    with open(CSV_PATH, newline="") as f:
        rows = list(csv.DictReader(f))

    print(f"Loaded {len(rows)} participants.")

    tasks = build_tasks(rows)
    pending = [(url, dest) for url, dest in tasks if not os.path.exists(dest)]
    skipped = len(tasks) - len(pending)

    print(f"{len(tasks)} total files  |  {skipped} already done  |  {len(pending)} to download")

    if not pending:
        print("Nothing to do.")
        return

    errors = 0
    with tqdm(total=len(pending), unit="file", dynamic_ncols=True) as bar:
        # Sequential but with a thread pool for overlap between download and conversion
        from concurrent.futures import ThreadPoolExecutor, as_completed

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
            futures = {pool.submit(download_and_convert, url, dest): dest for url, dest in pending}
            for future in as_completed(futures):
                ok = future.result()
                if not ok:
                    errors += 1
                bar.update(1)

    print(f"\nDone — {len(pending) - errors} saved, {errors} errors.")
    print(f"  {PASSAGE_DIR}")
    print(f"  {TRIALS_PARTICIPANT_DIR}")
    print(f"  {TRIALS_MODEL_DIR}")


if __name__ == "__main__":
    main()

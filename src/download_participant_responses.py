#!/usr/bin/env python3
"""
Download participant trial recordings from participants_results_filtered.csv.

Run with:
    conda run -n SLM python src/download_participant_responses.py

Output: audio/participant_responses/

Naming convention:
  {user_id}_trial{XX}_{gender}_{voice_condition}.wav

Gender is normalized from the free-text demo_gender field to female/male.
"""

import csv
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from tqdm import tqdm

CSV_PATH = os.path.join(os.path.dirname(__file__), "../experiment_results/participants_results_filtered.csv")
OUT_DIR = os.path.join(os.path.dirname(__file__), "../audio/participant_responses")

MAX_WORKERS = 8

# "File Playback Issues" group from the participant audit, plus
# user_1776838509472_273 (all recordings empty on Firebase). Kept in the
# trust/anthropomorphism data but excluded from acoustic analysis.
AUDIO_EXCLUDE = {
    "user_1776281879521_93",
    "user_1776880934785_963",
    "user_1777086359782_475",
    "user_1777320645524_903",
    "user_1777141644215_473",
    "user_1776838509472_273",
}

GENDER_MAP = {
    "female": "female", "f": "female", "woman": "female",
    "male": "male", "m": "male", "man": "male",
}


def normalize_gender(raw: str) -> str:
    return GENDER_MAP.get(raw.strip().lower(), "unknown")


def convert_to_wav(src: str, dest: str) -> None:
    # Omit -ar and -ac so ffmpeg keeps the source sample rate and channel count unchanged.
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-acodec", "pcm_s16le", dest],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def download_and_convert(url: str, dest_wav: str) -> bool:
    with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as tmp:
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
    tasks = []
    for row in rows:
        user_id = row["user_id"].strip()
        if user_id in AUDIO_EXCLUDE:
            continue
        condition = row["voice_condition"].strip()
        gender = normalize_gender(row.get("demo_gender", ""))

        for trial_n in range(1, 21):
            url = row.get(f"trial_{trial_n:02d}_participant_recording", "").strip()
            if url:
                name = f"{user_id}_trial{trial_n:02d}_{gender}_{condition}.wav"
                tasks.append((url, os.path.join(OUT_DIR, name)))
    return tasks


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)

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
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
            futures = {pool.submit(download_and_convert, url, dest): dest for url, dest in pending}
            for future in as_completed(futures):
                if not future.result():
                    errors += 1
                bar.update(1)

    print(f"\nDone — {len(pending) - errors} saved, {errors} errors.")
    print(f"  {os.path.abspath(OUT_DIR)}")


if __name__ == "__main__":
    main()

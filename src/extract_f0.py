#!/usr/bin/env python3
"""
F0 extraction for participant trial recordings, adapted from the vspy
get_pitch_praat feature (parselmouth / Praat filtered autocorrelation).

Run with:
    conda run -n vspy python src/extract_f0.py

Input:  audio/participant_responses/{user_id}_trial{XX}_{gender}_{condition}.wav
Output: audio/acoustic_output/trials_f0.csv — one row per recording with
        metadata and Mean_f0_Interval_1..15 (mean F0 in Hz over 15 equal
        time intervals; NaN where an interval has no voiced frames).
"""

import os
import re
import sys
import warnings
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import pandas as pd
import parselmouth

AUDIO_DIR = os.path.join(os.path.dirname(__file__), "../audio/participant_responses")
OUT_CSV = os.path.join(os.path.dirname(__file__), "../audio/acoustic_output/trials_f0.csv")

N_INTERVALS = 15
MAX_WORKERS = 8

FILENAME_RE = re.compile(
    r"^(?P<participant>user_\d+_\d+)_trial(?P<trial>\d+)_"
    r"(?P<gender>female|male|unknown)_(?P<condition>natural|robotic)\.wav$"
)


# vspy/features/get_pitch_praat.py, unchanged except datalen is computed
# from the sound when not supplied.
def get_pitch_praat(
    wavfile,
    frameshift_ms=1,
    datalen=None,
    min_f0=40,
    max_f0=500,
    sil_threshold=0.03,
    voicing_threshold=0.45,
    octave_cost=0.01,
    octave_jump_cost=0.35,
    voiced_unvoiced_cost=0.14,
):
    snd = parselmouth.Sound(str(wavfile))
    frameshift_s = frameshift_ms / 1000
    if datalen is None:
        datalen = int(snd.get_total_duration() * 1000 / frameshift_ms)
    pitch = snd.to_pitch_cc(
        time_step=frameshift_s,
        pitch_floor=min_f0,
        pitch_ceiling=max_f0,
        silence_threshold=sil_threshold,
        voicing_threshold=voicing_threshold,
        octave_cost=octave_cost,
        octave_jump_cost=octave_jump_cost,
        voiced_unvoiced_cost=voiced_unvoiced_cost,
    )
    times = pitch.xs()
    f0_values = pitch.selected_array["frequency"]

    f0 = np.full(datalen, np.nan)
    for t, f in zip(times, f0_values):
        i = round(t * 1000 / frameshift_ms)
        if 0 <= i < datalen:
            f0[i] = f if f > 0 else np.nan  # praat returns 0 for unvoiced

    return f0


def interval_means(f0: np.ndarray, n_intervals: int = N_INTERVALS) -> list[float]:
    """Mean voiced F0 within n equal time intervals across the recording."""
    edges = np.linspace(0, len(f0), n_intervals + 1).round().astype(int)
    means = []
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", category=RuntimeWarning)  # all-NaN intervals
        for lo, hi in zip(edges[:-1], edges[1:]):
            means.append(float(np.nanmean(f0[lo:hi])) if hi > lo else np.nan)
    return means


def process_file(filename: str) -> dict:
    meta = FILENAME_RE.match(filename).groupdict()
    f0 = get_pitch_praat(os.path.join(AUDIO_DIR, filename))
    row = {
        "Filename": filename,
        "participant": meta["participant"],
        "trial": int(meta["trial"]),
        "gender": meta["gender"],
        "voice_condition": meta["condition"],
    }
    for k, mean in enumerate(interval_means(f0), start=1):
        row[f"Mean_f0_Interval_{k}"] = mean
    return row


def main() -> None:
    files = sorted(f for f in os.listdir(AUDIO_DIR) if FILENAME_RE.match(f))
    skipped = sorted(f for f in os.listdir(AUDIO_DIR) if f.endswith(".wav") and not FILENAME_RE.match(f))
    if skipped:
        print(f"WARNING: {len(skipped)} wav files did not match the naming pattern:", file=sys.stderr)
        for f in skipped:
            print(f"  {f}", file=sys.stderr)

    print(f"Extracting F0 from {len(files)} recordings...")

    rows = []
    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as pool:
        for n, row in enumerate(pool.map(process_file, files), start=1):
            rows.append(row)
            if n % 100 == 0 or n == len(files):
                print(f"  {n}/{len(files)}")

    df = pd.DataFrame(rows).sort_values(["participant", "trial"])
    os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)
    df.to_csv(OUT_CSV, index=False)

    f0_cols = [f"Mean_f0_Interval_{k}" for k in range(1, N_INTERVALS + 1)]
    n_vals = df[f0_cols].notna().sum().sum()
    print(f"Saved {len(df)} rows to {os.path.abspath(OUT_CSV)}")
    print(f"Voiced interval coverage: {n_vals}/{len(df) * N_INTERVALS} "
          f"({100 * n_vals / (len(df) * N_INTERVALS):.1f}%)")


if __name__ == "__main__":
    main()

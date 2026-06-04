# SLM Experiment

## Overview

This project examines how the perceived naturalness of a text-to-speech (TTS) voice affects human responses to AI-generated advice. Participants were randomly assigned to interact with either a **natural** or a **robotic** TTS voice and completed 20 advice trials across five domains: Career, Cooking, Health, Medication, and Travel.

The central question: does a more human-sounding voice lead people to anthropomorphize, trust, or rely on AI advice more?

**N = 74 participants**, ~1,479 trial-level observations.

---

## Repository Structure

```
src/                  # R and Python analysis scripts
  analysis.R          # Main behavioral analysis (trust, accuracy, validation)
  f0_processing.R     # F0 extraction and GAM modeling
  count.R             # Participant counting / data summaries
  download_audio.py   # Audio download utility

audio/                # Raw audio files from participant sessions
experiment/           # Experiment stimuli and task files
experiment_results/   # Raw result exports
figures/              # Generated plots referenced in results docs
models/               # Saved model objects
results_summary.md    # Behavioral results (anthropomorphism, trust, reliance)
results_acoustic.md   # Speaking rate and intensity analysis
results_gam_f0.md     # F0 contour GAM analysis
```

---

## Design

- **Between-subjects:** each participant heard only one voice condition (natural or robotic)
- **Trials:** 20 advice prompts per participant, spanning 5 domains (4 trials each)
- **Outcomes measured per participant:** anthropomorphism scale (0–30), emotional trust (0–4), overall trust (1–5), collaborator trust (1–5)
- **Outcomes measured per trial:** perceived accuracy (1–4), error risk (1–4), validation intent (0–2)
- **Acoustic outcomes:** speaking rate (syll/s), intensity (dB), F0 (z-scored semitones, gender-normalized)

---

## Initial Findings

### Voice condition changed perception but not behavior

The manipulation worked: participants in the natural voice condition rated the AI as significantly more human-like (anthropomorphism β = +1.61, p < .001, R² = .16). But this perceptual shift did not carry over into trust or behavioral reliance. Across all six downstream measures — emotional trust, overall trust, collaborator trust, perceived accuracy, error risk, and validation — not a single voice condition effect reached p < .05. Voice changed how the AI *seemed*, not how people *used* it.

### Domain context was the dominant driver of behavioral outcomes

Topic area had large, consistent effects on all three trial-level outcomes:

- **Medication** prompted the highest error risk (+0.47 above grand mean) and most frequent validation (+0.32), alongside the lowest perceived accuracy (−0.12)
- **Career** elicited the lowest error risk (−0.56) and least validation (−0.17), suggesting participants felt most capable of evaluating this advice themselves
- **Cooking** was rated most accurate (+0.13) and prompted low validation (−0.19)
- None of the domain effects interacted with voice condition

### Perceived accuracy declined over the session

A small but reliable linear decline in perceived accuracy was observed across the 20 trials (β = −0.008/trial, p = .002), amounting to roughly a 0.15-point cumulative drop. No corresponding decline appeared for error risk or validation — pointing to accuracy judgments specifically, rather than a global shift in engagement.

### Acoustic differences between TTS voices were real but partially converged over trials

- The robotic voice was significantly faster (+0.73 syll/s, p < .001) and louder (+5.06 dB, p < .001) than the natural voice
- The intensity gap attenuated over trials via a significant condition × trial interaction (p = .002): the natural voice grew louder across the session while the robotic voice remained flat
- **F0 (pitch):** mean F0 level did not differ between conditions (participant-level Welch t-test: t(70) = −0.57, p = .569). F0 contour shape was also identical. Both conditions showed nonlinear trial-by-trial F0 trends, but the conditions did not differ from each other

---

## Analysis Stack

- **R:** `lme4`, `lmerTest` (mixed models), `mgcv` / `ggplot2` (GAMs, plots)
- **Praat:** acoustic feature extraction via scripting toolbox
- **Python:** audio download and preprocessing

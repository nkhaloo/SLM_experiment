# GAM Results: F0 by TTS Condition

## Model specification

```
f0_st ~ TTS_condition +
    s(time, k = 10) +
    s(time, by = TTS_condition, k = 10) +
    s(trial, by = TTS_condition, k = 10) +
    s(participant, bs = "re") +
    s(trial_fac, bs = "re") +
    s(time, participant, bs = "fs", m = 1, k = 8)
```

- **Outcome:** Speaker-normalized F0 in semitones — each speaker's grand mean F0 (computed across all their trials and intervals) was subtracted, so values represent deviations from the speaker's own baseline pitch. This removes absolute F0 differences between speakers (e.g. male vs. female).
- **Time** centered at interval 8 (midpoint of the 15-interval contour), so the intercept = F0 at the utterance midpoint
- **Smooths:** `s(time)` and `s(time, by = TTS_condition)` use a thin-plate spline (k = 10); `s(trial, by = TTS_condition)` captures nonlinear learning trends (k = 10); `s(time, participant, bs = "fs")` gives each participant their own contour deviation (factor smooth, k = 8); random intercepts for participant and trial via `bs = "re"`
- **Estimation:** `bam()` with fREML and `discrete = TRUE` for efficiency
- **N:** 19,005 observations (1,267 trials × 15 intervals)
- **R² (adj):** 0.352 — after speaker normalization, the model explains 36.4% of remaining within-speaker variance

---

## Speaker sample

The sample consisted of 71 speakers. Per-speaker grand mean F0 ranged from 112 Hz to 259 Hz, with a grand mean of **205 Hz** — indicating a predominantly female sample (typical male speaking F0 is ~85–180 Hz; female ~165–255 Hz). Only approximately 5 speakers fell in the male range. This sex imbalance motivated speaker normalization, as unequal condition assignment of male vs. female participants would otherwise confound the TTS condition effect.

---

## Parametric terms

| Term | Estimate | SE | t | p |
|---|---|---|---|---|
| Intercept (natural, midpoint) | −1.83 st | 0.27 | −6.69 | < .001 |
| TTS condition: robotic | +4.52 st | 0.12 | 39.13 | < .001 |

The intercept represents the natural condition at the utterance midpoint: participants' F0 sat **1.83 st below their own mean** when shadowing natural speech. The robotic condition was **4.52 semitones higher** than natural — a large, highly significant effect.

### What 4.52 semitones means in Hz

A difference of 4.52 st corresponds to a multiplicative factor of 2^(4.52/12) ≈ **1.30**, meaning robotic-condition F0 was approximately **30% higher in Hz** than natural. At the grand mean speaker baseline of 205 Hz, this translates to roughly:

- Natural (midpoint): 205 × 2^(−1.83/12) ≈ **185 Hz**
- Robotic (midpoint): 205 × 2^(2.69/12) ≈ **240 Hz**
- **Difference: ~55 Hz**

Note: before speaker normalization the raw condition estimate was 5.91 st, suggesting that ~1.4 st of the apparent effect was attributable to a sex/speaker confound (more female speakers in the robotic condition).

---

## Smooth terms

| Smooth | edf | F | p |
|---|---|---|---|
| s(time) — overall contour | 5.54 | 12.50 | < .001 |
| s(time) × natural | 1.00 | 0.02 | .881 |
| s(time) × robotic | 1.25 | 0.29 | .566 |
| s(trial) × natural | 8.29 | 13.83 | < .001 |
| s(trial) × robotic | 1.00 | 2.13 | .144 |
| s(participant) — random intercept | 34.91 | — | .992 |
| s(trial_fac) — random intercept | 15.60 | — | .540 |
| s(time, participant) — random contours | 290.44 | — | 1.000 |

### F0 contour shape

The overall time smooth (edf = 5.54) is significant, capturing a falling declination pattern across the utterance that is shared across both conditions. Neither the natural nor robotic by-condition smooth deviates significantly from this shared shape (p = .881 and p = .566), meaning the two conditions produce the **same F0 contour shape** — robotic is shifted uniformly upward rather than shaped differently.

### Trial-by-trial trend

There is a highly significant nonlinear trend over trial number in the **natural** condition (edf = 8.29, p < .001), indicating that participants' normalized F0 fluctuated in a complex, non-monotonic pattern across trials when shadowing natural speech. The **robotic** condition shows no such trend (p = .144), remaining essentially flat across trials. The amplitude of the natural condition trend is modest (~1–2 st peak-to-trough), but its high edf suggests structured — rather than random — variation.

---

## Data processing notes

- Raw trials: 1,410
- Dropped for < 8 voiced intervals: 22
- Dropped as Mahalanobis outliers (D > 6, computed on normalized contours): 121
- Final: 1,267 trials
- Missing edge intervals were filled by row-wise linear interpolation prior to outlier filtering
- F0 converted to semitones re: 1 Hz via 12 × log₂(Hz), then speaker-normalized by subtracting each speaker's grand mean

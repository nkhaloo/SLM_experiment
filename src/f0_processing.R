library(tidyverse)
library(zoo)
library(lme4)
library(lmerTest)

figures_dir <- "figures_colorblind"
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)
condition_colors <- c(natural = "#4D4D4D", robotic = "#BDBDBD")

# ── Load ──────────────────────────────────────────────────────────────────────
# Produced by src/extract_f0.py (parselmouth / Praat CC pitch tracker):
# one row per recording with participant, trial, gender, voice_condition
# parsed from the filename, and Mean_f0_Interval_1..15 in Hz.
raw <- read_csv(
  "audio/acoustic_output/trials_f0.csv",
  na = c("", "NA", "NaN"),
  show_col_types = FALSE
)

f0_cols <- paste0("Mean_f0_Interval_", 1:15)

df <- raw |>
  select(Filename, voice_condition, participant, trial, gender, all_of(f0_cols))

# ── Outlier filtering: MAD (k = 3) on raw F0 (Hz), within gender ─────────────
# Each F0 measurement is compared to its gender's median across all raw Hz
# values; measurements beyond k robust SDs (mad() includes the 1.4826
# consistency constant) are set to NA. This targets pitch-tracking artifacts
# (octave doubling/halving), which sit far outside the gender's F0 range.
mad_k <- 3

gender_mad <- df |>
  pivot_longer(all_of(f0_cols), values_to = "hz") |>
  filter(!is.na(hz)) |>
  group_by(gender) |>
  summarise(med_hz = median(hz), mad_hz = mad(hz), .groups = "drop")

cat("Gender-specific raw F0 median and MAD (Hz):\n")
print(gender_mad)

n_vals_before <- sum(!is.na(df[, f0_cols]))
df <- df |>
  left_join(gender_mad, by = "gender") |>
  mutate(across(all_of(f0_cols),
                ~ if_else(abs(.x - med_hz) / mad_hz > mad_k, NA_real_, .x))) |>
  select(-med_hz, -mad_hz)
n_mad_removed <- n_vals_before - sum(!is.na(df[, f0_cols]))
cat(sprintf("F0 measurements removed (|z_MAD| > %g, within gender): %d of %d (%.1f%%)\n",
            mad_k, n_mad_removed, n_vals_before, 100 * n_mad_removed / n_vals_before))

# Keep the cleaned Hz values for raw-Hz plotting
df_hz_clean <- df

# ── Convert Hz → semitones (re: 1 Hz) ────────────────────────────────────────
df <- df |>
  mutate(across(all_of(f0_cols), ~ 12 * log2(.x)))

# ── Gender-based Z-score normalization ───────────────────────────────────────
gender_stats <- df |>
  pivot_longer(all_of(f0_cols), values_to = "f0_st") |>
  group_by(gender) |>
  summarise(
    f0_mean = mean(f0_st, na.rm = TRUE),
    f0_sd   = sd(f0_st,   na.rm = TRUE),
    .groups = "drop"
  )

cat("Gender-specific F0 mean and SD (semitones):\n")
print(gender_stats)

# Z-score within gender: (x - gender_mean) / gender_sd
df <- df |>
  left_join(gender_stats, by = "gender") |>
  mutate(across(all_of(f0_cols), ~ (.x - f0_mean) / f0_sd)) |>
  select(-f0_mean, -f0_sd)

# ── Drop rows with too few voiced intervals ───────────────────────────────────
# Unvoiced edges produce NA; rows below this threshold are unrecoverable.
min_voiced <- 8

n_voiced    <- rowSums(!is.na(df[, f0_cols]))
df_enough   <- df[n_voiced >= min_voiced, ]
n_low_voiced <- nrow(df) - nrow(df_enough)

# ── Row-wise linear interpolation (fills remaining edge NAs) ──────────────────
f0_mat <- as.matrix(df_enough[, f0_cols])
f0_mat <- t(apply(f0_mat, 1, \(row) na.approx(row, na.rm = FALSE, rule = 2)))

df_interp <- df_enough
df_interp[, f0_cols] <- as.data.frame(f0_mat)

df_filtered <- df_interp

# ── Report ────────────────────────────────────────────────────────────────────
cat(sprintf(
  "Utterances in: %d | Dropped (<%d voiced after MAD filter): %d | Out: %d\n",
  nrow(df), min_voiced, n_low_voiced, nrow(df_filtered)
))

# ── Pivot to long format: one row per F0 value ────────────────────────────────
# Columns: voice_condition, participant, trial, time (centered: -7..+7), f0
df_long <- df_filtered |>
  pivot_longer(all_of(f0_cols), names_to = "time", values_to = "f0") |>
  mutate(time = as.integer(str_extract(time, "\\d+$")) - 8L) |>
  select(voice_condition, participant, trial, time, f0)

# ── Save ──────────────────────────────────────────────────────────────────────
write_csv(df_long, "audio/acoustic_output/trials_f0_semitones_long.csv")

# ── F0 linear mixed model ─────────────────────────────────────────────────────
# f0 ~ voice_condition * time + (1 + time | participant) + (1 | utterance)
# - voice_condition (sum-coded: natural = +1, robotic = -1): mean F0 level
#   difference between groups, tested against between-participant variability
# - time (centered at utterance midpoint): linear declination slope
# - voice_condition x time: condition difference in declination slope
# - (1 + time | participant): per-speaker baseline pitch and declination slope
# - (1 | utterance): the 15 points within an utterance are correlated
df_mod <- df_long |>
  mutate(
    voice_condition = factor(voice_condition, levels = c("natural", "robotic")),
    utterance       = paste(participant, trial, sep = "_")
  )
cond_cm <- contr.sum(2)
colnames(cond_cm) <- levels(df_mod$voice_condition)[1]
contrasts(df_mod$voice_condition) <- cond_cm

lmm_f0 <- lmer(
  f0 ~ voice_condition * time + (1 + time | participant) + (1 | utterance),
  data = df_mod, REML = TRUE
)

cat("\n── F0 ~ voice condition * time + (1 + time | participant) + (1 | utterance) ──\n")
print(summary(lmm_f0), correlation = FALSE)
if (!dir.exists("models")) dir.create("models")
saveRDS(lmm_f0, "models/lmm_f0.rds")

# ── Raw F0 (Hz) contours, faceted by gender ───────────────────────────────────
# Uses the MAD-cleaned Hz values (pre-normalization) for the same utterances
# that survived filtering. Removed/unvoiced intervals stay NA here (no
# interpolation), so per-point means use only retained measurements.
hz_long <- df_hz_clean |>
  semi_join(df_filtered, by = "Filename") |>
  pivot_longer(all_of(f0_cols), names_to = "time", values_to = "f0_hz") |>
  mutate(time = as.integer(str_extract(time, "\\d+$")) - 8L) |>
  filter(!is.na(f0_hz), !is.na(gender))

hz_plot_df <- hz_long |> mutate(gender = str_to_title(gender))

# Loess smoothing over the utterance-level measurements (95% CI ribbons)
p_raw_contour <- ggplot(
  hz_plot_df,
  aes(x = time, y = f0_hz, color = voice_condition, fill = voice_condition,
      linetype = voice_condition)
) +
  geom_smooth(method = "loess", span = 0.75, se = TRUE, alpha = 0.2) +
  facet_wrap(~ gender, scales = "free_y") +
  scale_color_manual(values = condition_colors) +
  scale_fill_manual(values = condition_colors) +
  scale_linetype_manual(values = c(natural = "solid", robotic = "dashed")) +
  scale_x_continuous(breaks = seq(-7, 7, 2)) +
  labs(
    x = "Normalized Time (centered)",
    y = "F0 (Hz)",
    color = "Voice condition", fill = "Voice condition",
    linetype = "Voice condition"
  ) +
  theme_minimal() +
  theme(
    axis.text = element_text(size = 14),
    axis.title = element_text(size = 17),
    strip.text = element_text(size = 16, face = "bold"),
    legend.title = element_text(size = 15),
    legend.text = element_text(size = 14)
  )

ggsave(file.path(figures_dir, "raw_f0_contour.png"), p_raw_contour,
       width = 10, height = 4, dpi = 300)

# NOTE: the previous speaking-rate & intensity section relied on the PRAAT
# toolbox output (trials.csv), which is superseded by the parselmouth F0
# extraction. Those measures would need their own extraction step to rerun.

# ── Pitch range ───────────────────────────────────────────────────────────────
# Per-utterance pitch range: max - min of the 15 interval F0 values
# (semitones, z-scored within gender), from the same cleaned/interpolated
# data as the contour model.
range_df <- df_long |>
  group_by(voice_condition, participant, trial) |>
  summarise(pitch_range = max(f0) - min(f0), .groups = "drop")

range_summary <- range_df |>
  group_by(voice_condition) |>
  summarise(
    n      = n(),
    mean   = mean(pitch_range),
    sd     = sd(pitch_range),
    median = median(pitch_range),
    .groups = "drop"
  )

cat("\nPitch range (z-scored semitones) by condition:\n")
print(range_summary)

# ── Pitch range contour across trial number ───────────────────────────────────
# Loess smooth over utterance-level values by condition (95% CI ribbons),
# same style as the raw F0 contour above.
p_range <- ggplot(
  range_df,
  aes(x = trial, y = pitch_range, color = voice_condition, fill = voice_condition)
) +
  geom_smooth(method = "loess", span = 0.75, se = TRUE, alpha = 0.2, linewidth = 0.9) +
  scale_color_manual(values = condition_colors) +
  scale_fill_manual(values = condition_colors) +
  scale_x_continuous(breaks = seq(2, 20, 2)) +
  labs(
    x = "Trial Number",
    y = "Pitch Range (z-scored semitones)",
    color = "Voice condition", fill = "Voice condition"
  ) +
  theme_minimal()

ggsave(file.path(figures_dir, "pitch_range_by_trial.png"), p_range,
       width = 8, height = 4.5, dpi = 300)

p_range_box <- ggplot(range_df, aes(x = voice_condition, y = pitch_range,
                                    fill = voice_condition)) +
  geom_boxplot(width = 0.6, outlier.alpha = 0.35) +
  scale_fill_manual(values = condition_colors) +
  labs(x = "Voice condition", y = "Pitch Range (z-scored semitones)") +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14),
    axis.title = element_text(size = 17)
  )

ggsave(file.path(figures_dir, "pitch_range_boxplot.png"), p_range_box,
       width = 6, height = 4.5, dpi = 300)

# ── Pitch range linear mixed model ────────────────────────────────────────────
# pitch_range ~ voice_condition * trial_c + (1 + trial_c | participant)
# - voice_condition (sum-coded: natural = +1, robotic = -1), as in the F0 model
# - trial_c: trial number centered at mid-session, so the condition main effect
#   is evaluated at the session midpoint rather than at trial 0
# - voice_condition x trial_c: do trial trajectories differ between conditions?
# - (1 + trial_c | participant): per-speaker baseline range and trial slope
range_mod <- range_df |>
  mutate(
    voice_condition = factor(voice_condition, levels = c("natural", "robotic")),
    trial_c         = trial - mean(trial)
  )
contrasts(range_mod$voice_condition) <- cond_cm

lmm_range <- lmer(
  pitch_range ~ voice_condition * trial_c + (1 + trial_c | participant),
  data = range_mod, REML = TRUE
)

cat("\n── Pitch range ~ voice condition * trial + (1 + trial | participant) ──\n")
print(summary(lmm_range), correlation = FALSE)
saveRDS(lmm_range, "models/lmm_pitch_range.rds")

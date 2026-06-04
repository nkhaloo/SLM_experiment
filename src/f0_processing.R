library(tidyverse)
library(zoo)
library(mgcv)

# ── Load ──────────────────────────────────────────────────────────────────────
raw <- read_csv(
  "audio/acoustic_output/trials.csv",
  na = c("", "NA", "--undefined--"),
  show_col_types = FALSE
)

f0_cols <- paste0("Mean_f0_Interval_", 1:15)

# ── Parse filename metadata & keep only trial rows ────────────────────────────
df <- raw |>
  filter(str_detect(Filename, "_trial_")) |>
  mutate(
    TTS_condition = str_extract(Filename, "^[^_]+"),
    participant = str_extract(Filename, "(?<=_)(user\\d+)(?=_)"),
    trial       = as.integer(str_extract(Filename, "(?<=trial_)\\d+"))
  ) |>
  select(Filename, TTS_condition, participant, trial, all_of(f0_cols))

# ── Convert Hz → semitones (re: 1 Hz) ────────────────────────────────────────
df <- df |>
  mutate(across(all_of(f0_cols), ~ 12 * log2(.x)))

# ── Gender-based Z-score normalization ───────────────────────────────────────
# Load gender from participant metadata; user number = row order in CSV.
participant_meta <- read_csv(
  "experiment_results/participants_results_filtered.csv",
  show_col_types = FALSE
) |>
  mutate(
    participant = paste0("user", row_number()),
    gender = case_when(
      str_to_lower(demo_gender) %in% c("female", "f", "woman") ~ "female",
      str_to_lower(demo_gender) %in% c("male", "m", "man")     ~ "male",
      TRUE ~ NA_character_
    )
  ) |>
  select(participant, gender)

# Gender-specific mean and SD across all F0 observations
gender_stats <- df |>
  left_join(participant_meta, by = "participant") |>
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
  left_join(participant_meta, by = "participant") |>
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

# ── Outlier filtering via Mahalanobis distance ────────────────────────────────
f0_matrix  <- as.matrix(df_interp[, f0_cols])
cov_mat    <- cov(f0_matrix)
center     <- colMeans(f0_matrix)
mahal_dist <- mahalanobis(f0_matrix, center = center, cov = cov_mat)

df_filtered <- df_interp |>
  mutate(mahal_dist = sqrt(mahal_dist)) |>  # mahalanobis() returns D², take sqrt
  filter(mahal_dist <= 6)

# ── Report ────────────────────────────────────────────────────────────────────
n_raw      <- nrow(df)
n_outliers <- nrow(df_interp) - nrow(df_filtered)

cat(sprintf(
  "Rows in: %d | Dropped (<%d voiced): %d | Dropped (Mahal>6): %d | Out: %d\n",
  n_raw, min_voiced, n_low_voiced, n_outliers, nrow(df_filtered)
))

# ── Pivot to long format & center time at midpoint (interval 8 = 0) ──────────
df_long <- df_filtered |>
  pivot_longer(all_of(f0_cols), names_to = "interval", values_to = "f0_st") |>
  mutate(
    interval = as.integer(str_extract(interval, "\\d+$")),
    time     = interval - 8L   # intercept = F0 at utterance midpoint
  )

# ── Save ──────────────────────────────────────────────────────────────────────
write_csv(df_long, "audio/acoustic_output/trials_f0_semitones_long.csv")

# ── Participant-level mean F0: between-subjects condition test ────────────────
# Design is between-subjects; participant is the proper unit of analysis for
# testing whether conditions differ in mean F0 level.
pp_means <- df_long |>
  group_by(participant, TTS_condition) |>
  summarise(mean_f0 = mean(f0_st, na.rm = TRUE), .groups = "drop")

cat("\nParticipant-level mean F0 per condition:\n")
pp_means |>
  group_by(TTS_condition) |>
  summarise(grand_mean = mean(mean_f0), sd = sd(mean_f0), n = n()) |>
  print()

pp_nat <- pp_means |> filter(TTS_condition == "natural") |> pull(mean_f0)
pp_rob <- pp_means |> filter(TTS_condition == "robotic") |> pull(mean_f0)
cat("\nWelch t-test (robotic vs natural, participant-level means):\n")
print(t.test(pp_rob, pp_nat))

# ── Participant-level F0 variability ──────────────────────────────────────────
# SD of F0 across all trials × intervals per participant (one value each)
pp_sd <- df_long |>
  group_by(participant, TTS_condition) |>
  summarise(f0_sd = sd(f0_st, na.rm = TRUE), .groups = "drop")

cat("\nParticipant-level F0 SD per condition:\n")
pp_sd |>
  group_by(TTS_condition) |>
  summarise(mean_sd = mean(f0_sd), sd_sd = sd(f0_sd), n = n()) |>
  print()

sd_nat <- pp_sd |> filter(TTS_condition == "natural") |> pull(f0_sd)
sd_rob <- pp_sd |> filter(TTS_condition == "robotic") |> pull(f0_sd)
cat("\nWelch t-test (robotic vs natural, participant-level F0 SD):\n")
print(t.test(sd_rob, sd_nat))

pp_sd_lm <- pp_sd |>
  mutate(TTS_condition = factor(TTS_condition, levels = c("natural", "robotic")))
contrasts(pp_sd_lm$TTS_condition) <- c(-0.5, 0.5)

lm_f0sd <- lm(f0_sd ~ TTS_condition, data = pp_sd_lm)
cat("\n── F0 SD ~ TTS condition (participant-level) ──\n")
print(summary(lm_f0sd))

p_f0_sd <- ggplot(pp_sd, aes(x = TTS_condition, y = f0_sd, fill = TTS_condition)) +
  geom_boxplot(alpha = 0.7, outlier.shape = NA, width = 0.5) +
  geom_jitter(width = 0.1, size = 1.5, alpha = 0.6) +
  scale_fill_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "TTS condition",
    y = "F0 SD (semitones, Z-scored)",
  ) +
  labs(fill = "TTS condition") +
  theme_minimal()

ggsave("figures/f0_sd_by_condition.png", p_f0_sd, width = 5, height = 4, dpi = 150)

# ── Fit GAM ───────────────────────────────────────────────────────────────────
df_gam <- df_long |>
  mutate(
    TTS_condition = factor(TTS_condition, levels = c("natural", "robotic")),
    participant   = factor(participant),
    trial_fac     = factor(trial)
  )

# TTS_condition:           parametric term — mean F0 difference between conditions
# s(time):                 overall F0 contour (reference smooth)
# s(time, by=...):         condition-specific contour shape differences
# s(trial, by=...):        nonlinear trend over trial number per condition
# s(participant, re):      random intercept per participant
# s(trial_fac, re):        random intercept per trial item
# s(time, participant, fs): participant-specific contour deviations
m1 <- bam(
  f0_st ~ TTS_condition +
    s(time, k = 10) +
    s(time, by = TTS_condition, k = 10) +
    s(trial, by = TTS_condition, k = 10) +
    s(trial_fac, bs = "re"),
  data     = df_gam,
  method   = "fREML",
  discrete = TRUE
)

summary(m1)
saveRDS(m1, "models/gam_f0.rds")

# ── Plot smooths ──────────────────────────────────────────────────────────────
conditions <- c("natural", "robotic")
time_seq   <- seq(-7, 7, length.out = 200)

excl <- c("s(trial_fac)")

gam_predict <- function(nd) {
  p <- predict(m1, newdata = nd, exclude = excl, type = "response", se.fit = TRUE)
  nd$f0_pred <- p$fit
  nd$se      <- p$se.fit
  nd
}

# Predicted F0 contour per condition (excluding random effects)
pred_time <- map_dfr(conditions, \(cond) {
  nd <- data.frame(
    TTS_condition = factor(cond, levels = conditions),
    time          = time_seq,
    trial         = median(df_gam$trial),
    participant   = factor(levels(df_gam$participant)[1]),
    trial_fac     = factor(levels(df_gam$trial_fac)[1])
  )
  gam_predict(nd) |> mutate(TTS_condition = cond)
})

p_contour <- ggplot(
  pred_time, aes(x = time, y = f0_pred, color = TTS_condition, fill = TTS_condition)
) +
  geom_ribbon(aes(ymin = f0_pred - 1.96 * se, ymax = f0_pred + 1.96 * se),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  scale_fill_manual(values  = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Normalized Time (centered)",
    y = "F0 (semitones, Z-scored)",
    color = "TTS condition", fill = "TTS condition"
  ) +
  theme_minimal()

# Trial trend per condition
trial_seq <- seq(min(df_gam$trial), max(df_gam$trial), length.out = 200)

pred_trial <- map_dfr(conditions, \(cond) {
  nd <- data.frame(
    TTS_condition = factor(cond, levels = conditions),
    time          = 0L,
    trial         = trial_seq,
    participant   = factor(levels(df_gam$participant)[1]),
    trial_fac     = factor(levels(df_gam$trial_fac)[1])
  )
  gam_predict(nd) |> mutate(TTS_condition = cond)
})

p_trial <- ggplot(
  pred_trial, aes(x = trial, y = f0_pred, color = TTS_condition, fill = TTS_condition)
) +
  geom_ribbon(aes(ymin = f0_pred - 1.96 * se, ymax = f0_pred + 1.96 * se),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  scale_fill_manual(values  = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Trial Number",
    y = "F0 (semitones, Z-scored)",
    color = "TTS condition", fill = "TTS condition"
  ) +
  theme_minimal()

ggsave("figures/gam_f0_contour.png", p_contour, width = 7, height = 4, dpi = 150)
ggsave("figures/gam_f0_trial_trend.png", p_trial,   width = 7, height = 4, dpi = 150)

# ── Raw F0 contours (observed means across intervals) ─────────────────────────
raw_f0_summary <- df_long |>
  group_by(TTS_condition, time) |>
  summarise(
    mean_f0 = mean(f0_st, na.rm = TRUE),
    se_f0   = sd(f0_st, na.rm = TRUE) / sqrt(sum(!is.na(f0_st))),
    .groups = "drop"
  )

p_raw_contour <- ggplot(
  raw_f0_summary,
  aes(x = time, y = mean_f0, color = TTS_condition, fill = TTS_condition)
) +
  geom_ribbon(aes(ymin = mean_f0 - 1.96 * se_f0, ymax = mean_f0 + 1.96 * se_f0),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  scale_fill_manual(values  = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Normalized Time (centered)",
    y = "F0 (semitones, Z-scored)",
    color = "TTS condition", fill = "TTS condition"
  ) +
  theme_minimal()

ggsave("figures/raw_f0_contour.png", p_raw_contour, width = 7, height = 4, dpi = 150)

# ── Participant-averaged F0 contour (between-subjects unit of analysis) ────────
# Step 1: average each participant's F0 across all trials, per time point
pp_contour <- df_long |>
  group_by(participant, TTS_condition, time) |>
  summarise(mean_f0 = mean(f0_st, na.rm = TRUE), .groups = "drop")

# Step 2: average participant means per condition, SE across participants
pp_contour_summary <- pp_contour |>
  group_by(TTS_condition, time) |>
  summarise(
    grand_mean = mean(mean_f0, na.rm = TRUE),
    se         = sd(mean_f0, na.rm = TRUE) / sqrt(n()),
    .groups    = "drop"
  )

p_pp_contour <- ggplot(
  pp_contour_summary,
  aes(x = time, y = grand_mean, color = TTS_condition, fill = TTS_condition)
) +
  geom_ribbon(aes(ymin = grand_mean - 1.96 * se, ymax = grand_mean + 1.96 * se),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  scale_fill_manual(values  = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Normalized Time (centered)",
    y = "F0 (semitones, Z-scored)",
    color = "TTS condition", fill = "TTS condition"
  ) +
  theme_minimal()

ggsave("figures/participant_avg_f0_contour.png", p_pp_contour, width = 7, height = 4, dpi = 150)

# ── Speaking rate & intensity ─────────────────────────────────────────────────
library(lme4)
library(lmerTest)

acoustic_trials <- raw |>
  filter(str_detect(Filename, "_trial_")) |>
  mutate(
    TTS_condition = factor(str_extract(Filename, "^[^_]+")),
    participant   = str_extract(Filename, "user[0-9]+"),
    trial         = as.integer(str_extract(Filename, "(?<=trial_)[0-9]+"))
  ) |>
  select(TTS_condition, participant, trial, speakingrate, Intensity)

# Mahalanobis outlier filtering on (speakingrate, Intensity) jointly
ac_complete   <- acoustic_trials[complete.cases(acoustic_trials[, c("speakingrate", "Intensity")]), ]
ac_mat        <- as.matrix(ac_complete[, c("speakingrate", "Intensity")])
ac_mahal      <- sqrt(mahalanobis(ac_mat, colMeans(ac_mat), cov(ac_mat)))
acoustic_trials <- ac_complete[ac_mahal <= 6, ]

cat(sprintf(
  "Acoustic: %d trials in | %d incomplete | %d outliers (Mahal>6) | %d out\n",
  nrow(ac_complete) + sum(!complete.cases(raw[str_detect(raw$Filename, "_trial_"), c("speakingrate", "Intensity")])),
  sum(!complete.cases(acoustic_trials[, c("speakingrate", "Intensity")])),
  sum(ac_mahal > 6),
  nrow(acoustic_trials)
))

# sum code condition: intercept = grand mean, coefficient = robotic - natural
contrasts(acoustic_trials$TTS_condition) <- c(-0.5, 0.5)

# participant means for bar plots
acoustic_means <- acoustic_trials |>
  group_by(TTS_condition, participant) |>
  summarise(
    speakingrate = mean(speakingrate, na.rm = TRUE),
    Intensity    = mean(Intensity,    na.rm = TRUE),
    .groups = "drop"
  )

# mixed models: condition × trial + random intercept for participant
lmer_sr  <- lmer(
  speakingrate ~ TTS_condition * trial + (1 | participant),
  data = acoustic_trials, REML = TRUE
)
lmer_int <- lmer(
  Intensity ~ TTS_condition * trial + (1 | participant),
  data = acoustic_trials, REML = TRUE
)
cat("\n── Speaking rate ~ TTS condition * trial + (1|participant) ──\n")
print(summary(lmer_sr))
cat("\n── Intensity ~ TTS condition * trial + (1|participant) ──\n")
print(summary(lmer_int))

# smoothed line plots using loess directly on trial-level data
plot_by_trial <- function(data, var, ylab) {
  ggplot(data, aes(x = trial, y = .data[[var]],
                   color = TTS_condition, fill = TTS_condition)) +
    geom_smooth(method = "loess", span = 0.75, se = TRUE, alpha = 0.2) +
    scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
    scale_fill_manual(values  = c(natural = "#2196F3", robotic = "#F44336")) +
    labs(x = "Trial number", y = ylab,
         color = "TTS condition", fill = "TTS condition") +
    theme_minimal()
}

p_sr  <- plot_by_trial(acoustic_trials, "speakingrate", "Speaking rate (syll/s)")
p_int <- plot_by_trial(acoustic_trials, "Intensity", "Intensity (dB)")

ggsave("figures/speakingrate_by_trial.png", p_sr,  width = 7, height = 4, dpi = 150)
ggsave("figures/intensity_by_trial.png",    p_int, width = 7, height = 4, dpi = 150)


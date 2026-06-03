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

# ── Speaker normalization (subtract each speaker's grand mean) ────────────────
# Centers every speaker at 0 so male/female baseline differences are removed.
# Values become semitone deviations from the speaker's own mean F0.
speaker_means <- df |>
  pivot_longer(all_of(f0_cols), values_to = "f0_st") |>
  group_by(participant) |>
  summarise(speaker_mean = mean(f0_st, na.rm = TRUE), .groups = "drop")

grand_mean_st <- mean(speaker_means$speaker_mean)  # for back-converting plots

df <- df |>
  left_join(speaker_means, by = "participant") |>
  mutate(across(all_of(f0_cols), ~ .x - speaker_mean)) |>
  select(-speaker_mean)

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
    s(participant, bs = "re") +
    s(trial_fac,   bs = "re") +
    s(time, participant, bs = "fs", m = 1, k = 8),
  data     = df_gam,
  method   = "fREML",
  discrete = TRUE
)

summary(m1)
saveRDS(m1, "models/gam_f0.rds")

# ── Plot smooths ──────────────────────────────────────────────────────────────
conditions <- c("natural", "robotic")
time_seq   <- seq(-7, 7, length.out = 200)

# Predicted F0 contour per condition (excluding random effects)
pred_time <- map_dfr(conditions, \(cond) {
  nd <- data.frame(
    TTS_condition = factor(cond, levels = conditions),
    time          = time_seq,
    trial         = median(df_gam$trial),
    participant   = factor(levels(df_gam$participant)[1]),
    trial_fac     = factor(levels(df_gam$trial_fac)[1])
  )
  nd$f0_pred <- predict(
    m1, newdata = nd,
    exclude = c("s(participant)", "s(trial_fac)", "s(time,participant)"),
    type = "response"
  )
  nd$TTS_condition <- cond
  nd
})

p_contour <- ggplot(
  pred_time, aes(x = time, y = f0_pred, color = TTS_condition)
) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Time (intervals, 0 = midpoint)",
    y = "F0 (semitones, speaker-normalized)",
    color = "TTS condition",
    title = "Predicted F0 contour by TTS condition"
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
  nd$f0_pred <- predict(
    m1, newdata = nd,
    exclude = c("s(participant)", "s(trial_fac)", "s(time,participant)"),
    type = "response"
  )
  nd$TTS_condition <- cond
  nd
})

p_trial <- ggplot(
  pred_trial, aes(x = trial, y = f0_pred, color = TTS_condition)
) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(natural = "#2196F3", robotic = "#F44336")) +
  labs(
    x = "Trial number",
    y = "F0 (semitones, speaker-normalized)",
    color = "TTS condition",
    title = "F0 trend over trials by TTS condition"
  ) +
  theme_minimal()

ggsave("figures/gam_f0_contour.png", p_contour, width = 7, height = 4, dpi = 150)
ggsave("figures/gam_f0_trial_trend.png", p_trial,   width = 7, height = 4, dpi = 150)


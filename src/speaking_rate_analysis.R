library(tidyverse)
library(lme4)
library(lmerTest)

figures_dir <- "figures_colorblind"
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)
condition_colors <- c(natural = "#4D4D4D", robotic = "#BDBDBD")

# ── Load ──────────────────────────────────────────────────────────────────────
# Produced by the PRAAT acoustic analysis toolbox
# (!Acoustic_analysis_toolbox_PRAAT_2025): one row per recording;
# speakingrate = voiced syllable peaks / total duration (syll/sec).
# The toolbox writes one trailing blank row, dropped by the Filename filter.
raw <- read_csv(
  "audio/acoustic_output/acoustic_measurements_trials.csv",
  na = c("", "NA", "--undefined--"),
  show_col_types = FALSE
)

df <- raw |>
  filter(!is.na(Filename), Filename != "") |>
  mutate(
    participant     = str_extract(Filename, "^user_\\d+_\\d+"),
    trial           = as.integer(str_extract(Filename, "(?<=trial)\\d+")),
    gender          = str_extract(Filename, "female|male"),
    voice_condition = str_extract(Filename, "natural|robotic"),
    speakingrate    = as.numeric(speakingrate)
  ) |>
  filter(!is.na(speakingrate)) |>
  select(Filename, participant, trial, gender, voice_condition, speakingrate)

# ── Outlier filtering: MAD (k = 3) on speaking rate ──────────────────────────
# Same robust rule as the F0 filter in f0_processing.R: drop utterances whose
# speaking rate is more than k robust SDs from the median (mad() includes the
# 1.4826 consistency constant). This targets near-silent recordings (rate ~ 0)
# and tracking artifacts. Applied pooled, not within condition, so the filter
# cannot bias the natural-vs-robotic comparison.
mad_k <- 3
rate_med <- median(df$speakingrate)
rate_mad <- mad(df$speakingrate)

n_before <- nrow(df)
df <- df |>
  filter(abs(speakingrate - rate_med) / rate_mad <= mad_k)
cat(sprintf(
  "Speaking-rate outliers removed (|z_MAD| > %g): %d of %d (%.1f%%)\n",
  mad_k, n_before - nrow(df), n_before, 100 * (n_before - nrow(df)) / n_before
))

# ── Summary by condition ──────────────────────────────────────────────────────
rate_summary <- df |>
  group_by(voice_condition) |>
  summarise(
    n      = n(),
    mean   = mean(speakingrate),
    sd     = sd(speakingrate),
    median = median(speakingrate),
    .groups = "drop"
  )

cat("Speaking rate (syllables/sec) by condition:\n")
print(rate_summary)

# ── Speaking rate contour across trial number ─────────────────────────────────
# Loess smooth over utterance-level values by condition (95% CI ribbons),
# same style as the raw F0 contour in f0_processing.R.
p_rate <- ggplot(
  df,
  aes(x = trial, y = speakingrate, color = voice_condition, fill = voice_condition)
) +
  geom_smooth(method = "loess", span = 0.75, se = TRUE, alpha = 0.2, linewidth = 0.9) +
  scale_color_manual(values = condition_colors) +
  scale_fill_manual(values = condition_colors) +
  scale_x_continuous(breaks = seq(2, 20, 2)) +
  labs(
    x = "Trial Number",
    y = "Speaking Rate (syllables/sec)",
    color = "Voice condition", fill = "Voice condition"
  ) +
  theme_minimal()

ggsave(file.path(figures_dir, "speaking_rate_by_trial.png"), p_rate,
       width = 8, height = 4.5, dpi = 300)

p_rate_box <- ggplot(df, aes(x = voice_condition, y = speakingrate,
                             fill = voice_condition)) +
  geom_boxplot(width = 0.6, outlier.alpha = 0.35) +
  scale_fill_manual(values = condition_colors) +
  labs(x = "Voice condition", y = "Speaking Rate (syllables/sec)") +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14),
    axis.title = element_text(size = 17)
  )

ggsave(file.path(figures_dir, "speaking_rate_boxplot.png"), p_rate_box,
       width = 6, height = 4.5, dpi = 300)

# ── Speaking rate linear mixed model ──────────────────────────────────────────
# speakingrate ~ voice_condition * trial_c + (1 + trial_c | participant)
# - voice_condition (sum-coded: natural = +1, robotic = -1), as in the F0 models
# - trial_c: trial number centered at mid-session, so the condition main effect
#   is evaluated at the session midpoint rather than at trial 0
# - voice_condition x trial_c: do trial trajectories differ between conditions?
# - (1 | participant): random intercept only; a per-speaker trial slope was
#   singular (slope variance ~ 0), so it is dropped
rate_mod <- df |>
  mutate(
    voice_condition = factor(voice_condition, levels = c("natural", "robotic")),
    trial_c         = trial - mean(trial)
  )
cond_cm <- contr.sum(2)
colnames(cond_cm) <- levels(rate_mod$voice_condition)[1]
contrasts(rate_mod$voice_condition) <- cond_cm

lmm_rate <- lmer(
  speakingrate ~ voice_condition * trial_c + (1 | participant),
  data = rate_mod, REML = TRUE
)

cat("\n── Speaking rate ~ voice condition * trial + (1 | participant) ──\n")
print(summary(lmm_rate), correlation = FALSE)
if (!dir.exists("models")) dir.create("models")
saveRDS(lmm_rate, "models/lmm_speaking_rate.rds")

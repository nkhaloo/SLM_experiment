library(tidyverse)
library(lme4)
library(lmerTest)

# Participant-level communicative-competence ratings
ratings <- read_csv(
  "experiment_results/participants_results_filtered.csv",
  show_col_types = FALSE
) |>
  distinct(user_id, anth_competence) |>
  rename(participant = user_id, competence = anth_competence) |>
  mutate(competence_c = competence - mean(competence, na.rm = TRUE))

# Cleaned, gender-normalized F0 values produced by src/f0_processing.R.
# Aggregate the 15 time-normalized measurements to one mean and one range per
# utterance so all three outcomes are analyzed at the trial level.
f0_trials <- read_csv(
  "audio/acoustic_output/trials_f0_semitones_long.csv",
  show_col_types = FALSE
) |>
  group_by(participant, voice_condition, trial) |>
  summarise(
    mean_f0 = mean(f0),
    pitch_range = max(f0) - min(f0),
    .groups = "drop"
  )

# Speaking-rate extraction and the same pooled MAD filter used in the primary
# speaking-rate analysis.
rate_trials <- read_csv(
  "audio/acoustic_output/acoustic_measurements_trials.csv",
  na = c("", "NA", "--undefined--"),
  show_col_types = FALSE
) |>
  filter(!is.na(Filename), Filename != "") |>
  mutate(
    participant = str_extract(Filename, "^user_\\d+_\\d+"),
    trial = as.integer(str_extract(Filename, "(?<=trial)\\d+")),
    voice_condition = str_extract(Filename, "natural|robotic"),
    speaking_rate = as.numeric(speakingrate)
  ) |>
  filter(!is.na(speaking_rate))

rate_median <- median(rate_trials$speaking_rate)
rate_mad <- mad(rate_trials$speaking_rate)
rate_trials <- rate_trials |>
  filter(abs(speaking_rate - rate_median) / rate_mad <= 3) |>
  select(participant, voice_condition, trial, speaking_rate)

prepare_model_data <- function(data) {
  data |>
    inner_join(ratings, by = "participant") |>
    mutate(
      voice_condition = factor(voice_condition, levels = c("natural", "robotic")),
      trial_c = trial - mean(trial)
    )
}

f0_model_data <- prepare_model_data(f0_trials)
rate_model_data <- prepare_model_data(rate_trials)

sum_contrasts <- contr.sum(2)
colnames(sum_contrasts) <- "natural"
contrasts(f0_model_data$voice_condition) <- sum_contrasts
contrasts(rate_model_data$voice_condition) <- sum_contrasts

# Competence is the focal between-participant predictor. Voice condition,
# centered trial, and their interaction retain the primary model controls.
mean_f0_model <- lmer(
  mean_f0 ~ competence_c + voice_condition * trial_c +
    (1 + trial_c | participant),
  data = f0_model_data,
  REML = TRUE
)

pitch_range_model <- lmer(
  pitch_range ~ competence_c + voice_condition * trial_c +
    (1 + trial_c | participant),
  data = f0_model_data,
  REML = TRUE
)

speaking_rate_model <- lmer(
  speaking_rate ~ competence_c + voice_condition * trial_c +
    (1 | participant),
  data = rate_model_data,
  REML = TRUE
)

# Descriptive participant means plus the adjusted fixed-effect competence slope
# from the mean-F0 mixed model (voice and trial contrasts held at their grand
# means). Points are horizontally jittered because competence is a 1--5 rating.
participant_f0 <- f0_model_data |>
  group_by(participant, voice_condition, competence, competence_c) |>
  summarise(mean_f0 = mean(mean_f0), .groups = "drop")

competence_grid <- tibble(
  competence = seq(min(participant_f0$competence),
                   max(participant_f0$competence), length.out = 100),
  competence_c = competence - mean(ratings$competence, na.rm = TRUE)
)

fixed_estimates <- fixef(mean_f0_model)
fixed_vcov <- vcov(mean_f0_model)
prediction_matrix <- cbind(
  `(Intercept)` = 1,
  competence_c = competence_grid$competence_c,
  voice_conditionnatural = 0,
  trial_c = 0,
  `voice_conditionnatural:trial_c` = 0
)
prediction_matrix <- prediction_matrix[, names(fixed_estimates), drop = FALSE]
competence_grid$estimate <- as.vector(prediction_matrix %*% fixed_estimates)
competence_grid$se <- sqrt(diag(prediction_matrix %*% fixed_vcov %*%
                                  t(prediction_matrix)))

competence_f0_plot <- ggplot(
  participant_f0,
  aes(x = competence, y = mean_f0, fill = voice_condition)
) +
  geom_ribbon(
    data = competence_grid,
    aes(x = competence, ymin = estimate - 1.96 * se,
        ymax = estimate + 1.96 * se),
    inherit.aes = FALSE,
    fill = "#BDBDBD",
    alpha = 0.45
  ) +
  geom_line(
    data = competence_grid,
    aes(x = competence, y = estimate),
    inherit.aes = FALSE,
    color = "black",
    linewidth = 1.1
  ) +
  geom_point(
    position = position_jitter(width = 0.08, height = 0),
    shape = 21,
    color = "black",
    size = 3,
    alpha = 0.8
  ) +
  scale_fill_manual(
    values = c(natural = "#4D4D4D", robotic = "#BDBDBD"),
    labels = c(natural = "Natural", robotic = "Robotic")
  ) +
  scale_x_continuous(breaks = 1:5) +
  labs(
    x = "Perceived Communicative Competence Rating",
    y = "Mean F0 (gender-standardized semitones)",
    fill = "Voice condition"
  ) +
  theme_minimal() +
  theme(
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14),
    axis.title = element_text(size = 16),
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 13),
    legend.position = "top"
  )

if (!dir.exists("figures_colorblind")) dir.create("figures_colorblind")
ggsave(
  "figures_colorblind/competence_mean_f0.png",
  competence_f0_plot,
  width = 8,
  height = 5.5,
  dpi = 300,
  bg = "white"
)

# Discrete-rating alternative: adjusted point estimates and 95% confidence
# intervals at each observed response category, with participant means behind.
rating_estimates <- tibble(
  competence = sort(unique(participant_f0$competence)),
  competence_c = competence - mean(ratings$competence, na.rm = TRUE)
)
rating_matrix <- cbind(
  `(Intercept)` = 1,
  competence_c = rating_estimates$competence_c,
  voice_conditionnatural = 0,
  trial_c = 0,
  `voice_conditionnatural:trial_c` = 0
)
rating_matrix <- rating_matrix[, names(fixed_estimates), drop = FALSE]
rating_estimates$estimate <- as.vector(rating_matrix %*% fixed_estimates)
rating_estimates$se <- sqrt(diag(rating_matrix %*% fixed_vcov %*%
                                   t(rating_matrix)))
rating_counts <- participant_f0 |> count(competence)

competence_f0_interval_plot <- ggplot(
  participant_f0,
  aes(x = competence, y = mean_f0, fill = voice_condition)
) +
  geom_point(
    position = position_jitter(width = 0.08, height = 0),
    shape = 21,
    color = "#666666",
    size = 2.7,
    alpha = 0.45
  ) +
  geom_errorbar(
    data = rating_estimates,
    aes(x = competence, ymin = estimate - 1.96 * se,
        ymax = estimate + 1.96 * se),
    inherit.aes = FALSE,
    width = 0.08,
    linewidth = 1,
    color = "black"
  ) +
  geom_point(
    data = rating_estimates,
    aes(x = competence, y = estimate),
    inherit.aes = FALSE,
    shape = 18,
    size = 4,
    color = "black"
  ) +
  geom_text(
    data = rating_counts,
    aes(x = competence, y = min(participant_f0$mean_f0) - 0.08,
        label = paste0("n = ", n)),
    inherit.aes = FALSE,
    size = 4.5
  ) +
  scale_fill_manual(
    values = c(natural = "#4D4D4D", robotic = "#BDBDBD"),
    labels = c(natural = "Natural", robotic = "Robotic")
  ) +
  scale_x_continuous(breaks = sort(unique(participant_f0$competence))) +
  labs(
    x = "Perceived Communicative Competence Rating",
    y = "Mean F0 (gender-standardized semitones)",
    fill = "Voice condition"
  ) +
  theme_minimal() +
  theme(
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14),
    axis.title = element_text(size = 16),
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 13),
    legend.position = "top"
  )

ggsave(
  "figures_colorblind/competence_mean_f0_point_interval.png",
  competence_f0_interval_plot,
  width = 8,
  height = 5.5,
  dpi = 300,
  bg = "white"
)

cat("Participants with competence and F0 data:",
    n_distinct(f0_model_data$participant), "\n")
cat("Participants with competence and speaking-rate data:",
    n_distinct(rate_model_data$participant), "\n")

for (model_name in c("MEAN F0", "PITCH RANGE", "SPEAKING RATE")) {
  model <- switch(
    model_name,
    "MEAN F0" = mean_f0_model,
    "PITCH RANGE" = pitch_range_model,
    "SPEAKING RATE" = speaking_rate_model
  )
  cat("\n=== COMPETENCE AND", model_name, "===\n")
  print(summary(model), correlation = FALSE)
}

if (!dir.exists("models")) dir.create("models")
saveRDS(mean_f0_model, "models/lmm_competence_mean_f0.rds")
saveRDS(pitch_range_model, "models/lmm_competence_pitch_range.rds")
saveRDS(speaking_rate_model, "models/lmm_competence_speaking_rate.rds")

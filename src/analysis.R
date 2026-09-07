library(tidyverse)
library(lme4)
library(lmerTest)

figures_dir <- "/Users/noahkhaloo/Desktop/SLM_experiment/figures_colorblind"
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

df <- read_csv(
  "/Users/noahkhaloo/Desktop/SLM_experiment/experiment_results/participants_results_filtered.csv"
) %>%
  pivot_longer(
    cols         = matches("^trial_[0-9]+_"),
    names_to     = c("trial", ".value"),
    names_pattern = "trial_([0-9]+)_(.*)"
  ) |>
  mutate(
    trial           = as.integer(trial),
    voice_condition = factor(voice_condition),
    domain          = factor(domain,
                             levels = c("Career", "Cooking", "Health", "Medication", "Travel")),
    type            = factor(type,
                             levels = c("Advice", "Estimation", "Fact", "Risk"))
  ) |>
  filter(!is.na(domain), !is.na(type),
         !is.na(accuracy), !is.na(reliance), !is.na(validation))

# Sum coding: voice_condition
vc_cm <- contr.sum(2)
colnames(vc_cm) <- levels(df$voice_condition)[1]
contrasts(df$voice_condition) <- vc_cm

# Sum coding: domain (Travel is last = implicit reference)
dom_cm <- contr.sum(nlevels(df$domain))
colnames(dom_cm) <- levels(df$domain)[-nlevels(df$domain)]
contrasts(df$domain) <- dom_cm

# Sum coding: question type (Risk is last = implicit reference)
type_cm <- contr.sum(nlevels(df$type))
colnames(type_cm) <- levels(df$type)[-nlevels(df$type)]
contrasts(df$type) <- type_cm

# ── Anthropomorphism ───────────────────────────────────────────────────────────
anth_df <- df |>
  distinct(user_id, voice_condition,
           anth_authenticity, anth_humanism, anth_awareness,
           anth_realism, anth_competence)

# Item-level Godspeed ratings by condition
anth_item_summary <- anth_df |>
  pivot_longer(
    c(anth_authenticity, anth_humanism, anth_awareness,
      anth_realism, anth_competence),
    names_to = "item",
    values_to = "score"
  ) |>
  mutate(
    item = factor(
      item,
      levels = c("anth_authenticity", "anth_humanism", "anth_awareness",
                 "anth_realism", "anth_competence"),
      labels = c("Authenticity", "Human-likeness", "Awareness",
                 "Realism", "Competence")
    )
  ) |>
  group_by(voice_condition, item) |>
  summarise(
    mean = mean(score, na.rm = TRUE),
    se = sd(score, na.rm = TRUE) / sqrt(sum(!is.na(score))),
    .groups = "drop"
  )

ggplot(
  anth_item_summary,
  aes(x = item, y = mean, fill = voice_condition)
) +
  geom_col(
    width = 0.7,
    position = position_dodge(width = 0.75)
  ) +
  geom_errorbar(
    aes(ymin = mean - se, ymax = mean + se),
    width = 0.12,
    position = position_dodge(width = 0.75)
  ) +
  labs(x = NULL, y = "Mean Item Rating", fill = "Voice condition") +
  scale_fill_manual(
    values = c(natural = "#4D4D4D", robotic = "#BDBDBD"),
    labels = c(natural = "Natural", robotic = "Robotic")
  ) +
  scale_y_continuous(breaks = 1:5) +
  coord_cartesian(ylim = c(1, 5)) +
  theme_minimal() +
  theme(
    legend.position = "top",
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 11),
    axis.title = element_text(size = 13, face = "bold")
  )

ggsave(
  file.path(figures_dir, "anthropomorphism_items_by_condition.png"),
  width = 8,
  height = 5,
  dpi = 300,
  bg = "white"
)

anth_models <- list(
  Authenticity = lm(anth_authenticity ~ voice_condition, data = anth_df),
  `Human-likeness` = lm(anth_humanism ~ voice_condition, data = anth_df),
  Awareness = lm(anth_awareness ~ voice_condition, data = anth_df),
  Realism = lm(anth_realism ~ voice_condition, data = anth_df),
  Competence = lm(anth_competence ~ voice_condition, data = anth_df)
)

for (item_name in names(anth_models)) {
  cat("\n=== ANTHROPOMORPHISM:", toupper(item_name), "===\n")
  print(summary(anth_models[[item_name]]))
}

# ── Trust components ───────────────────────────────────────────────────────────
trust_df <- df |>
  distinct(user_id, voice_condition,
           si_knowledgeable, si_best_interest, si_honest, si_unbiased,
           si_trustworthiness, si_collaborator) |>
  mutate(
    emotional_trust = si_knowledgeable + si_best_interest + si_honest + si_unbiased,
    overall_trust   = si_trustworthiness,
    collaborator    = si_collaborator
  )

plot_trust <- function(var, y_label, file_name, y_max) {
  summ <- trust_df |>
    group_by(voice_condition) |>
    summarise(
      mean = mean(.data[[var]], na.rm = TRUE),
      se   = sd(.data[[var]],   na.rm = TRUE) / sqrt(n()),
      .groups = "drop"
    )
  ggplot(summ, aes(x = voice_condition, y = mean, fill = voice_condition)) +
    geom_col() +
    geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
    labs(x = "Condition", y = y_label) +
    scale_fill_manual(values = c(natural = "#4D4D4D", robotic = "#BDBDBD")) +
    scale_y_continuous(limits = c(0, y_max), expand = expansion(mult = c(0, 0))) +
    theme_minimal() +
    theme(
      legend.position = "none",
      axis.line  = element_line(color = "black"),
      axis.text  = element_text(size = 14, face = "bold"),
      axis.title = element_text(size = 16, face = "bold")
    )
  ggsave(file.path(figures_dir, file_name), width = 6, height = 10)
}

plot_trust("emotional_trust", "Emotional Trust",   "emotional_trust_by_condition.png", 4)
plot_trust("overall_trust",   "Overall Trust",     "overall_trust_by_condition.png",    5)
plot_trust("collaborator",    "Collaborator Trust", "collaborator_by_condition.png",     5)

# Combined trust figure (emotional, overall, collaborator in one panel row)
trust_long <- trust_df |>
  pivot_longer(c(emotional_trust, overall_trust, collaborator),
               names_to = "measure", values_to = "score") |>
  group_by(voice_condition, measure) |>
  summarise(
    mean = mean(score, na.rm = TRUE),
    se   = sd(score,   na.rm = TRUE) / sqrt(sum(!is.na(score))),
    .groups = "drop"
  ) |>
  mutate(measure = factor(
    measure,
    levels = c("overall_trust", "emotional_trust", "collaborator"),
    labels = c("Overall Trust (1\u20135)",
               "Emotional Trust (0\u20134)",
               "Collaborator Trust (1\u20135)")
  ))

trust_caps <- tibble(
  measure = factor(levels(trust_long$measure),
                   levels = levels(trust_long$measure)),
  voice_condition = "natural",
  y_max = c(5, 4, 5)
)

ggplot(trust_long,
       aes(x = voice_condition, y = mean, fill = voice_condition)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
  geom_blank(data = trust_caps,
             aes(x = voice_condition, y = y_max), inherit.aes = FALSE) +
  facet_wrap(~ measure, scales = "free_y") +
  scale_fill_manual(values = c(natural = "#4D4D4D", robotic = "#BDBDBD")) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(x = "Condition", y = "Mean rating (\u00b1 SE)") +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line   = element_line(color = "black"),
    axis.text   = element_text(size = 13, face = "bold"),
    axis.title  = element_text(size = 15, face = "bold"),
    strip.text  = element_text(size = 14, face = "bold"),
    panel.spacing = unit(1.5, "lines")
  )
ggsave(file.path(figures_dir, "trust_by_condition.png"),
       width = 12, height = 4.5, dpi = 300, device = ragg::agg_png)

emotional_trust_model <- lm(emotional_trust ~ voice_condition, data = trust_df)
overall_trust_model   <- lm(overall_trust   ~ voice_condition, data = trust_df)
collaborator_model    <- lm(collaborator    ~ voice_condition, data = trust_df)

cat("\n=== EMOTIONAL TRUST ===\n");  print(summary(emotional_trust_model))
cat("\n=== OVERALL TRUST ===\n");    print(summary(overall_trust_model))
cat("\n=== COLLABORATOR TRUST ===\n"); print(summary(collaborator_model))

# ── Trial figures (unchanged) ──────────────────────────────────────────────────
trial_cond_summary <- df |>
  group_by(voice_condition) |>
  summarise(
    across(
      c(accuracy, reliance, validation),
      list(mean = ~mean(.x, na.rm = TRUE),
           se   = ~sd(.x, na.rm = TRUE) / sqrt(sum(!is.na(.x))))
    ),
    .groups = "drop"
  )

plot_by_condition <- function(outcome, y_label, file_name, y_max) {
  mean_col <- paste0(outcome, "_mean")
  se_col   <- paste0(outcome, "_se")
  ggplot(trial_cond_summary,
         aes(x = voice_condition, y = .data[[mean_col]], fill = voice_condition)) +
    geom_col() +
    geom_errorbar(aes(ymin = .data[[mean_col]] - .data[[se_col]],
                      ymax = .data[[mean_col]] + .data[[se_col]]), width = 0.2) +
    scale_fill_manual(values = c(natural = "#4D4D4D", robotic = "#BDBDBD")) +
    scale_y_continuous(limits = c(0, y_max), expand = expansion(mult = c(0, 0))) +
    labs(x = "Condition", y = y_label) +
    theme_minimal() +
    theme(
      legend.position = "none",
      axis.line  = element_line(color = "black"),
      axis.text  = element_text(size = 14, face = "bold"),
      axis.title = element_text(size = 16, face = "bold")
    )
  ggsave(file.path(figures_dir, file_name), width = 6, height = 10)
}

plot_by_condition("accuracy",   "Accuracy",               "accuracy_by_condition.png",   4)
plot_by_condition("reliance",   "Error Risk",              "reliance_by_condition.png",   4)
plot_by_condition("validation", "Likelihood to Validate",  "validation_by_condition.png", 2)

# ── Combined trial-outcome figure (accuracy, error risk, validation) ──────────
trial_cond_long <- trial_cond_summary |>
  pivot_longer(
    cols = -voice_condition,
    names_to = c("outcome", ".value"),
    names_pattern = "(accuracy|reliance|validation)_(mean|se)"
  ) |>
  # Display validation on a 1-3 scale (1 = No, 2 = Maybe, 3 = Yes)
  mutate(mean = if_else(outcome == "validation", mean + 1, mean)) |>
  mutate(outcome = factor(
    outcome,
    levels = c("accuracy", "reliance", "validation"),
    labels = c("Perceived Accuracy (1\u20134)",
               "Error Risk (1\u20134)",
               "Likelihood to Validate (1\u20133)")
  ))

# Invisible points pin each panel's y-axis to its full scale range
scale_caps <- tibble(
  outcome = factor(levels(trial_cond_long$outcome),
                   levels = levels(trial_cond_long$outcome)),
  voice_condition = "natural",
  y_max = c(4, 4, 3)
)

ggplot(trial_cond_long,
       aes(x = voice_condition, y = mean, fill = voice_condition)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
  geom_blank(data = scale_caps,
             aes(x = voice_condition, y = y_max), inherit.aes = FALSE) +
  facet_wrap(~ outcome, scales = "free_y") +
  scale_fill_manual(values = c(natural = "#4D4D4D", robotic = "#BDBDBD")) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(x = "Condition", y = "Mean rating (\u00b1 SE)") +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line   = element_line(color = "black"),
    axis.text   = element_text(size = 13, face = "bold"),
    axis.title  = element_text(size = 15, face = "bold"),
    strip.text  = element_text(size = 14, face = "bold"),
    panel.spacing = unit(1.5, "lines")
  )
ggsave(file.path(figures_dir, "trial_outcomes_by_condition.png"),
       width = 12, height = 4.5, dpi = 300, device = ragg::agg_png)

domain_cond_summary <- df |>
  group_by(voice_condition, domain) |>
  summarise(
    across(
      c(accuracy, reliance, validation),
      list(mean = ~mean(.x, na.rm = TRUE),
           se   = ~sd(.x, na.rm = TRUE) / sqrt(sum(!is.na(.x))))
    ),
    .groups = "drop"
  )

plot_by_domain <- function(outcome, y_label, y_max, file_name) {
  mean_col <- paste0(outcome, "_mean")
  se_col   <- paste0(outcome, "_se")
  ggplot(domain_cond_summary,
         aes(x = voice_condition, y = .data[[mean_col]], fill = voice_condition)) +
    geom_col() +
    geom_errorbar(aes(ymin = .data[[mean_col]] - .data[[se_col]],
                      ymax = .data[[mean_col]] + .data[[se_col]]), width = 0.2) +
    facet_wrap(~domain, nrow = 1) +
    scale_fill_manual(values = c(natural = "#4D4D4D", robotic = "#BDBDBD")) +
    scale_y_continuous(limits = c(0, y_max), expand = expansion(mult = c(0, 0))) +
    labs(x = "Condition", y = y_label) +
    theme_minimal() +
    theme(
      legend.position = "none",
      axis.line   = element_line(color = "black"),
      axis.text.x = element_text(size = 9, face = "bold", angle = 30, hjust = 1),
      axis.text.y = element_text(size = 10, face = "bold"),
      axis.title  = element_text(size = 13, face = "bold"),
      strip.text  = element_text(size = 11, face = "bold")
    )
  ggsave(file.path(figures_dir, file_name), width = 12, height = 5)
}

plot_by_domain("accuracy",   "Accuracy",               4, "accuracy_by_domain.png")
plot_by_domain("reliance",   "Error Risk",              4, "reliance_by_domain.png")
plot_by_domain("validation", "Likelihood to Validate",  2, "validation_by_domain.png")

# ── Per-trial mixed models ─────────────────────────────────────────────────────
fit_trial_model <- function(outcome) {
  f <- as.formula(paste(outcome, "~ voice_condition * domain * type + trial + (1 | user_id)"))
  m <- lmer(f, data = df, REML = FALSE)
  cat("\n===", toupper(outcome), "===\n")
  print(summary(m))
  m
}

accuracy_model   <- fit_trial_model("accuracy")
reliance_model   <- fit_trial_model("reliance")
validation_model <- fit_trial_model("validation")

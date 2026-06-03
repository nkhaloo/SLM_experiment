library(tidyverse)
library(lme4)
library(lmerTest)

figures_dir <- "/Users/noahkhaloo/Desktop/SLM_experiment/figures"

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
                             levels = c("Career", "Cooking", "Health", "Medication", "Travel"))
  ) |>
  filter(!is.na(domain), !is.na(accuracy), !is.na(reliance), !is.na(validation))

# Sum coding: voice_condition
vc_cm <- contr.sum(2)
colnames(vc_cm) <- levels(df$voice_condition)[1]
contrasts(df$voice_condition) <- vc_cm

# Sum coding: domain (Travel is last = implicit reference)
dom_cm <- contr.sum(nlevels(df$domain))
colnames(dom_cm) <- levels(df$domain)[-nlevels(df$domain)]
contrasts(df$domain) <- dom_cm

# ── Anthropomorphism ───────────────────────────────────────────────────────────
anth_df <- df |> distinct(user_id, voice_condition, anth_total_score)

anth_summary <- anth_df |>
  group_by(voice_condition) |>
  summarise(
    mean = mean(anth_total_score, na.rm = TRUE),
    se   = sd(anth_total_score,   na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

ggplot(anth_summary, aes(x = voice_condition, y = mean, fill = voice_condition)) +
  geom_col() +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
  labs(x = "Condition", y = "Anthropomorphism Total Score") +
  scale_y_continuous(limits = c(0, 25), expand = expansion(mult = c(0, 0))) +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line  = element_line(color = "black"),
    axis.text  = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 16, face = "bold")
  )
ggsave(file.path(figures_dir, "anthropomorphism_by_condition.png"), width = 6, height = 10)

anth_model <- lm(anth_total_score ~ voice_condition, data = anth_df)
cat("\n=== ANTHROPOMORPHISM ===\n")
print(summary(anth_model))

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
  f <- as.formula(paste(outcome, "~ voice_condition * domain + trial + (1 | user_id)"))
  m <- lmer(f, data = df, REML = FALSE)
  cat("\n===", toupper(outcome), "===\n")
  print(summary(m))
  m
}

accuracy_model   <- fit_trial_model("accuracy")
reliance_model   <- fit_trial_model("reliance")
validation_model <- fit_trial_model("validation")

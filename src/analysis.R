library(tidyverse)
library(lme4)
library(lmerTest)

figures_dir <- "/Users/noahkhaloo/Desktop/SLM_experiment/figures"

df <- read_csv(
  "/Users/noahkhaloo/Desktop/SLM_experiment/experiment_results/participants_results_filtered.csv"
) %>%
  pivot_longer(
    cols = matches("^trial_\\d+_"),
    names_to = c("trial", ".value"),
    names_pattern = "trial_(\\d+)_(.*)"
  ) |>
  mutate(
    trial = as.integer(trial),
    voice_condition = factor(voice_condition),
    domain = factor(domain)
  ) |>
  filter(!is.na(domain), !is.na(accuracy), !is.na(reliance), !is.na(validation))

vc_cm <- contr.sum(2)
colnames(vc_cm) <- levels(df$voice_condition)[1]
contrasts(df$voice_condition) <- vc_cm

dom_cm <- contr.sum(nlevels(df$domain))
colnames(dom_cm) <- levels(df$domain)[-nlevels(df$domain)]
contrasts(df$domain) <- dom_cm

# anthropomorphism
anth_summary <- df |>
  distinct(user_id, voice_condition, anth_total_score) |>
  group_by(voice_condition) |>
  summarise(
    mean = mean(anth_total_score, na.rm = TRUE),
    se = sd(anth_total_score, na.rm = TRUE) / sqrt(n()),
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
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 16, face = "bold")
  )
ggsave(file.path(figures_dir, "anthropomorphism_by_condition.png"), width = 6, height = 10)

anth_model <- lm(anth_total_score ~ voice_condition, data = df)
summary(anth_model)

# trust
trust_df <- df |>
  distinct(user_id, voice_condition,
           si_knowledgeable, si_best_interest, si_honest, si_unbiased,
           si_trustworthiness, si_collaborator) |>
  mutate(trust_total = si_knowledgeable + si_best_interest +
           si_honest + si_unbiased + si_trustworthiness + si_collaborator)

trust_summary <- trust_df |>
  group_by(voice_condition) |>
  summarise(
    mean = mean(trust_total, na.rm = TRUE),
    se = sd(trust_total, na.rm = TRUE) / sqrt(n()),
    .groups = "drop"
  )

ggplot(trust_summary, aes(x = voice_condition, y = mean, fill = voice_condition)) +
  geom_col() +
  geom_errorbar(aes(ymin = mean - se, ymax = mean + se), width = 0.2) +
  labs(x = "Condition", y = "Trust Total Score") +
  scale_y_continuous(limits = c(0, 14), expand = expansion(mult = c(0, 0))) +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.line = element_line(color = "black"),
    axis.text = element_text(size = 14, face = "bold"),
    axis.title = element_text(size = 16, face = "bold")
  )
ggsave(file.path(figures_dir, "trust_by_condition.png"), width = 6, height = 10)

trust_model <- lm(trust_total ~ voice_condition, data = trust_df)
summary(trust_model)

# Experimental trials: accuracy, error risk, likelihood to validate
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

plot_by_condition("accuracy",   "Accuracy",             "accuracy_by_condition.png",   4)
plot_by_condition("reliance",   "Error Risk",            "reliance_by_condition.png",   4)
plot_by_condition("validation", "Likelihood to Validate", "validation_by_condition.png", 2)

# Domain x condition plots
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

plot_by_domain("accuracy",   "Accuracy",             4, "accuracy_by_domain.png")
plot_by_domain("reliance",   "Error Risk",            4, "reliance_by_domain.png")
plot_by_domain("validation", "Likelihood to Validate", 2, "validation_by_domain.png")

# Mixed models: additive vs condition*domain interaction
model_formulas <- list(
  "additive"   = "~ voice_condition + domain + (1|user_id)",
  "vc*domain"  = "~ voice_condition * domain + (1|user_id)"
)

fit_models <- function(outcome) {
  formulas <- lapply(model_formulas, function(f) as.formula(paste(outcome, f)))
  models   <- lapply(formulas, function(f) lmer(f, data = df, REML = FALSE))

  aic_table <- data.frame(
    model = names(models),
    AIC   = sapply(models, AIC),
    BIC   = sapply(models, BIC)
  ) |> arrange(AIC)

  cat("\n===", toupper(outcome), ": model comparison (ranked by AIC) ===\n")
  print(aic_table)

  best_name <- aic_table$model[1]
  winner <- models[[best_name]]
  cat("\n===", toupper(outcome), ": winning model (", best_name, ") ===\n")
  print(summary(winner))
}

fit_models("accuracy")
fit_models("reliance")
fit_models("validation")

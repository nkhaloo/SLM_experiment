# Reproduce demographic-balance checks reported during manuscript preparation.
# Run from the repository root with:
#   Rscript src/demographic_balance_analysis.R

data_path <- file.path("experiment_results", "participants_results_filtered.csv")
df <- read.csv(data_path, stringsAsFactors = FALSE, check.names = FALSE)

df$condition <- factor(df$voice_condition, levels = c("natural", "robotic"))

gender_key <- tolower(trimws(df$demo_gender))
df$gender_group <- ifelse(
  gender_key %in% c("f", "female", "woman"), "Female/woman", "Male/man"
)

df$race_group <- ifelse(
  df$demo_ethnicity %in% c(
    "Asian American", "Hispanic/Latino American", "White American"
  ),
  df$demo_ethnicity,
  "Multiple/other"
)

df$language_group <- ifelse(
  df$demo_first_language == "English",
  "English only",
  "English and another language"
)

df$neuro_group <- ifelse(
  df$demo_neurodivergent == "No", "No", "Yes/prefer not to say"
)

df$ai_frequency_group <- ifelse(
  df$demo_ai_use_frequency %in% c("About once per day", "Several times per day"),
  "Daily or more",
  df$demo_ai_use_frequency
)

df$ai_attitude_group <- ifelse(
  grepl("negative", df$demo_ai_attitude, ignore.case = TRUE),
  "Negative",
  ifelse(grepl("positive", df$demo_ai_attitude, ignore.case = TRUE),
         "Positive", "Neutral")
)

run_chisq <- function(variable) {
  suppressWarnings(chisq.test(table(df[[variable]], df$condition), correct = FALSE))
}

age_test <- t.test(demo_age ~ condition, data = df)
gender_test <- run_chisq("gender_group")
race_test <- run_chisq("race_group")
language_test <- run_chisq("language_group")
frequency_test <- run_chisq("ai_frequency_group")
attitude_test <- run_chisq("ai_attitude_group")
neuro_test <- fisher.test(table(df$neuro_group, df$condition))

cat("Demographic balance across voice conditions\n\n")
cat("Condition counts\n")
print(table(df$condition))
cat("\nAge descriptives\n")
print(aggregate(demo_age ~ condition, df, function(x) c(M = mean(x), SD = sd(x))))
cat("\nWelch age test\n")
print(age_test)

for (item in list(
  Gender = list(variable = "gender_group", test = gender_test),
  `Race and ethnicity` = list(variable = "race_group", test = race_test),
  `First-language background` = list(variable = "language_group", test = language_test),
  `AI-use frequency` = list(variable = "ai_frequency_group", test = frequency_test),
  `Attitude toward AI` = list(variable = "ai_attitude_group", test = attitude_test)
)) {
  cat("\n", item$variable, "\n", sep = "")
  print(addmargins(table(df[[item$variable]], df$condition)))
  print(item$test)
}

cat("\nNeurodivergence response\n")
print(addmargins(table(df$neuro_group, df$condition)))
print(neuro_test)

cat("\nSpeech or hearing disorder\n")
print(addmargins(table(df$demo_speech_disorder, df$condition)))
cat("No test: all participants responded No.\n")

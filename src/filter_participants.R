library(tidyverse)
library(readxl)

# Participant filtering: exclude everyone listed in the audit spreadsheet under
# "No Response / Stopped Responding" and "Completely Blank / No Usable Metadata".

audit_path <- "/Users/noahkhaloo/Desktop/SLM_experiment/experiment_results/SpeechLLM Participant Audit.xlsx"
data_path <- "/Users/noahkhaloo/Desktop/SLM_experiment/experiment_results/participants_data.csv"
out_path <- "/Users/noahkhaloo/Desktop/SLM_experiment/experiment_results/participants_results_filtered.csv"

exclude_sections <- c(
  "No Response / Stopped Responding",
  "Completely Blank / No Usable Metadata"
)

# The audit sheet is a single column of user IDs broken into titled sections:
# any non-blank row that isn't a user ID starts a new section.
audit <- read_excel(audit_path, col_names = FALSE)
col1 <- str_trim(replace_na(pull(audit, 1), ""))
is_id <- str_detect(col1, regex("^user_", ignore_case = TRUE))
section <- if_else(col1 != "" & !is_id, col1, NA_character_)

audit_ids <- tibble(id = col1, section = section) |>
  fill(section) |>
  filter(str_detect(id, regex("^user_", ignore_case = TRUE)))

exclude_ids <- audit_ids |>
  filter(section %in% exclude_sections) |>
  pull(id) |>
  str_to_lower() |>
  unique()

cat(sprintf("Exclusion IDs from audit: %d unique\n", length(exclude_ids)))

df <- read_csv(data_path, show_col_types = FALSE)
df_filtered <- df |>
  filter(
    !str_to_lower(user_id) %in% exclude_ids,
    !is.na(demo_technologies_used),
    trimws(demo_technologies_used) != ""
  )

# Sanity check: warn about audit IDs that never appear in the data
missing <- setdiff(exclude_ids, str_to_lower(df$user_id))
if (length(missing) > 0) {
  cat("Audit IDs not found in participants_data.csv:\n")
  walk(missing, \(x) cat(" -", x, "\n"))
}

write_csv(df_filtered, out_path)
cat(sprintf(
  "Kept %d of %d participants (removed %d)\n",
  nrow(df_filtered), nrow(df), nrow(df) - nrow(df_filtered)
))

print(count(df_filtered, voice_condition, name = "n"))

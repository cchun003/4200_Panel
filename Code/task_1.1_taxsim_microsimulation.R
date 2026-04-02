# task_1.1_taxsim_microsimulation.R

# Setup Environment per User Feedback
print("Checking for required packages: usincometaxes, dplyr, readr...")
if (!requireNamespace("usincometaxes", quietly = TRUE)) {
  print("Installing usincometaxes from CRAN...")
  install.packages("usincometaxes", repos = "http://cran.us.r-project.org")
}
if (!requireNamespace("dplyr", quietly = TRUE)) {
  install.packages("dplyr", repos = "http://cran.us.r-project.org")
}
if (!requireNamespace("readr", quietly = TRUE)) {
  install.packages("readr", repos = "http://cran.us.r-project.org")
}

library(usincometaxes)
library(dplyr)
library(readr)

# Use dynamic context parsing if run from terminal
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args)
if (length(file_arg) > 0) {
  script_path <- sub("--file=", "", args[file_arg])
  base_dir <- dirname(script_path)
} else {
  base_dir <- getwd()
}

print("Initializing Data Streams...")

# Detect project root dynamically
if (dir.exists(file.path(base_dir, "Output"))) {
  proj_root <- base_dir
} else if (dir.exists(file.path(base_dir, "..", "Output"))) {
  proj_root <- file.path(base_dir, "..")
} else {
  proj_root <- base_dir # Fallback
}

acs_path <- file.path(proj_root, "Output", "acs_zcta_panel.csv")
cw_path  <- file.path(proj_root, "Data", "zcta_state_crosswalk.csv")

if (!file.exists(acs_path)) {
  stop(sprintf("Error: Cannot find ACS data at %s", acs_path))
}
if (!file.exists(cw_path)) {
  stop(sprintf("Error: Cannot find Crosswalk data at %s", cw_path))
}

acs_data <- read_csv(acs_path, show_col_types = FALSE)

# Due to Spanish characters, force latin1 encoding parsing
# Also, skip = 2 strictly to bypass Geocorr data-dictionary header
cw_hdr_p <- read_csv(cw_path, n_max = 1, show_col_types = FALSE)
cw <- read_csv(
  cw_path,
  skip = 2,
  col_names = colnames(cw_hdr_p),
  locale = locale(encoding = "latin1"),
  show_col_types = FALSE
)

print("Filtering Spatial Mismatch via Primary Population Logic...")
# Map ZCTAs to the state containing the definitive majority of its population
cw_clean <- cw |>
  filter(!is.na(zcta), trimws(zcta) != "") |>
  arrange(zcta, desc(pop20)) |>
  group_by(zcta) |>
  slice(1) |>
  ungroup() |>
  select(zcta, stab)

# Enforce standard string padding for exact joins
acs_data$ZCTA <- sprintf("%05s", as.character(acs_data$ZCTA))
cw_clean$zcta <- sprintf("%05s", as.character(cw_clean$zcta))

panel_merged <- acs_data |>
  left_join(cw_clean, by = c("ZCTA" = "zcta")) |>
  filter(!is.na(stab)) # Strictly remove unmappable geographic anomalies

print("Formatting Synthesized Homebuyer Profiles for TAXSIM Schema...")
# Implement exact deterministic user constraints: (pwages=Med, swages=0, mort=0)
taxsim_input <- panel_merged |>
  mutate(taxsimid = row_number()) |>
  select(taxsimid, year, ZCTA)

taxsim_df <- panel_merged |>
  mutate(taxsimid = row_number()) |>
  mutate(
    mstat = "married, jointly", # Modern usincometaxes parameter syntax
    depx = 2,
    page = 40,                  # Under TAXSIM 35
    sage = 40,
    state = stab,               # String abbreviation (e.g., 'CA', 'NY')
    pwages = as.integer(Median_Household_Income),
    swages = 0,                 # Defined assumption: zero secondary income
    proptax = as.integer(Median_Real_Estate_Taxes),
    mortgage = 0,               # Implicit TCJA standard deduction utilization
    year = pmin(year, 2023)     # Structural Fix: Cap simulation year natively
  ) |>
  select(
    taxsimid, year, mstat, depx, page, sage, state,
    pwages, swages, proptax, mortgage
  ) |>
  # Engine crashes if we send Puerto Rico (PR) or NAs
  filter(!is.na(pwages), !is.na(state), state %in% c(state.abb, "DC"))

print("Synthesized Dataset Formatted Successfully.")
msg <- paste(
  "Executing NBER TAXSIM Microsimulation Engine natively in R for",
  nrow(taxsim_df), "panel units..."
)
print(msg)

# Batch process TAXSIM
taxsim_results <- taxsim_calculate_taxes(
  .data = taxsim_df,
  return_all_information = FALSE
)

# taxsim_calculate_taxes generally returns fiitax (Federal), siitax (State).
print("Extracting Specific Liability Blocks (fiitax, siitax)...")
final_output <- panel_merged |>
  mutate(taxsimid = row_number()) |>
  left_join(
    taxsim_results |> select(taxsimid, fiitax, siitax),
    by = "taxsimid"
  ) |>
  select(-taxsimid) # Cleanup temporary index

# Save Panel
out_dir <- file.path(proj_root, "Output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
out_path <- file.path(out_dir, "taxsim_zcta_panel.csv")

write_csv(final_output, out_path)
msg <- paste(
  "TAXSIM structural microsimulation successfully saved to:",
  out_path
)
print(msg)

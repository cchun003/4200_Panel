# task_0.1_ipeds.R

# 1. Environment Setup
print("Checking for required packages: devtools, ipeds, dplyr, readr...")

if (!requireNamespace("devtools", quietly = TRUE)) {
  install.packages("devtools", repos = "http://cran.us.r-project.org")
}

if (!requireNamespace("ipeds", quietly = TRUE)) {
  print("Installing ipeds from GitHub...")
  devtools::install_github("jbryer/ipeds")
}

library(ipeds)
library(dplyr)
library(readr)

# Detect project root
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args)
if (length(file_arg) > 0) {
  script_path <- sub("--file=", "", args[file_arg])
  base_dir <- dirname(script_path)
} else {
  base_dir <- getwd()
}

if (dir.exists(file.path(base_dir, "Output"))) {
  proj_root <- base_dir
} else if (dir.exists(file.path(base_dir, "..", "Output"))) {
  proj_root <- file.path(base_dir, "..")
} else {
  proj_root <- base_dir
}

output_dir <- file.path(proj_root, "Output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

ipeds_data_dir <- file.path(proj_root, "Data", "IPEDS_Downloads")
options(ipeds.download.dir = ipeds_data_dir)

# 2. Data Extraction Function
get_table <- function(data_list, pattern) {
  # Find a table in the list that matches the given pattern
  match_idx <- grep(pattern, names(data_list), ignore.case = TRUE)
  if (length(match_idx) == 0) return(NULL)
  tbl <- data_list[[match_idx[1]]]
  names(tbl) <- tolower(names(tbl))
  return(tbl)
}

# 3. Processing Loop
years <- 2012:2024
state_tuition_list <- list()

print("Starting IPEDS extraction loop (2012-2024)...")

for (yr in years) {
  cat(sprintf("\n--- Processing Academic Year %d ---\n", yr))
  
  tryCatch({
    # Load all tables for the year
    data_list <- load_ipeds(year = yr)
    
    # Tables required:
    # 1. HD (Header) - State, Control
    # 2. IC_AY (Charges) - Tuition2 (In-state), Tuition3 (Out-of-state)
    # 3. SFA (Financial Aid) - SCFA12N (In-state count), SCFA13N (Out-of-state count)
    
    hd <- get_table(data_list, "^HD")
    ic_ay <- get_table(data_list, "^IC.*_AY")
    sfa <- get_table(data_list, "^SFA.*_P1")
    
    if (is.null(hd)) stop("HD table missing")
    if (is.null(ic_ay)) stop("IC_AY table missing")
    if (is.null(sfa)) stop("SFA Part 1 table missing")
    
    # SFA lookup variables (FTFT by tuition status)
    # scfa12n = Number of FTFT paying in-state
    # scfa13n = Number of FTFT paying out-of-state
    if (!all(c("scfa12n", "scfa13n") %in% names(sfa))) {
      stop("SFA count variables missing")
    }
    
    # Ensure unitid is numeric for reliable joining
    hd$unitid <- as.numeric(hd$unitid)
    ic_ay$unitid <- as.numeric(ic_ay$unitid)
    sfa$unitid <- as.numeric(sfa$unitid)
    
    # Merge on unitid
    merged <- hd |>
      select(unitid, stabbr, control) |>
      inner_join(
        ic_ay |> select(unitid, tuition2, tuition3), 
        by = "unitid"
      ) |>
      inner_join(
        sfa |> select(unitid, scfa12n, scfa13n), 
        by = "unitid"
      ) |>
      filter(control == 1) |> # Public
      mutate(
        tuition2 = as.numeric(tuition2),
        tuition3 = as.numeric(tuition3),
        enr_in_state = as.numeric(scfa12n),
        enr_out_state = as.numeric(scfa13n)
      ) |>
      # Clean data: must have tuition and at least one student in that group
      # Note: We keep the institution if it has either group, 
      # but it only contributes to the respective weighted average if n > 0.
      filter(!is.na(tuition2), !is.na(tuition3))
    
    if (nrow(merged) == 0) {
      warning("No valid public institutions found for this year.")
      next
    }
    
    # Aggregate to state level
    processed <- merged |>
      group_by(stabbr) |>
      summarize(
        year = yr,
        # Weighted avg using residence-specific counts
        weighted_in_state = sum(tuition2 * enr_in_state, na.rm = TRUE) / 
          sum(enr_in_state, na.rm = TRUE),
        weighted_out_of_state = sum(tuition3 * enr_out_state, na.rm = TRUE) / 
          sum(enr_out_state, na.rm = TRUE),
        inst_count = n(),
        total_in_state_enr = sum(enr_in_state, na.rm = TRUE),
        total_out_state_enr = sum(enr_out_state, na.rm = TRUE),
        .groups = "drop"
      )
    
    state_tuition_list[[as.character(yr)]] <- processed
    cat(sprintf("Successfully processed %d institutions in %d states.\n", 
                nrow(merged), nrow(processed)))
    
  }, error = function(e) {
    cat(sprintf("Error in year %d: %s\n", yr, e$message))
  })
}

# 4. Save Output
if (length(state_tuition_list) > 0) {
  final_panel <- bind_rows(state_tuition_list)
  
  # Forward-fill 2024 to 2025/2026
  data_2024 <- final_panel |> filter(year == 2024)
  if (nrow(data_2024) > 0) {
    data_2025 <- data_2024 |> mutate(year = 2025)
    data_2026 <- data_2024 |> mutate(year = 2026)
    final_panel <- bind_rows(final_panel, data_2025, data_2026)
  }
  
  out_path <- file.path(output_dir, "ipeds_tuition_panel.csv")
  write_csv(final_panel, out_path)
  cat(sprintf("\nSuccess! Panel saved to: %s\n", out_path))
} else {
  stop("No data collected across any years.")
}

library(ipeds)
options(ipeds.download.dir = "/Users/chenchun/Desktop/ECON4200/4200_Panel/Data/IPEDS_Downloads")

# Load HD survey for the most recent year to build the reference list
# of 4-year public degree-granting universities
tryCatch({
  data_2024 <- load_ipeds(2024)
  hd_name <- names(data_2024)[grep("^HD", names(data_2024))][1]
  hd <- data_2024[[hd_name]]
  names(hd) <- tolower(names(hd))

  # Filter criteria (IPEDS data dictionary):
  #   control == 1  : Public institution
  #   iclevel == 1  : Four-or-more year institution
  #   hloffer >= 5  : Highest offering is Bachelor's or above
  #   deggrant == 1 : Degree-granting status confirmed
  public_4yr <- hd[
    hd$control == 1 &
    hd$iclevel == 1 &
    hd$hloffer >= 5 &
    hd$deggrant == 1,
    c("unitid", "stabbr")
  ]

  write.csv(public_4yr, "Data/ipeds_public_universities.csv", row.names = FALSE)
  cat(sprintf(
    "Exported %d 4-year public degree-granting institutions to Data/ipeds_public_universities.csv\n",
    nrow(public_4yr)
  ))
}, error = function(e) {
  cat("Error exporting: ", e$message)
})

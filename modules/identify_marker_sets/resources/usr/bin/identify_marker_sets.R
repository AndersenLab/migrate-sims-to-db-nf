#!/usr/bin/env Rscript
# identify_marker_sets.R - Identify unique population+MAF combinations
#
# Usage: Rscript identify_marker_sets.R <mapping_files.csv>
# Output: marker_sets.csv with columns: population, maf, sample_file

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Usage: Rscript identify_marker_sets.R <mapping_files.csv>")
}

mapping_files_csv <- args[1]

if (!file.exists(mapping_files_csv)) {
  stop(paste("File not found:", mapping_files_csv))
}

# Read mapping files list
mapping_files <- read.csv(mapping_files_csv, stringsAsFactors = FALSE)

# Filter out unparseable files
valid_files <- mapping_files[!is.na(mapping_files$population), ]

if (nrow(valid_files) == 0) {
  cat("Warning: No valid mapping files found\n")
  result <- data.frame(
    population = character(),
    maf = numeric(),
    sample_file = character(),
    stringsAsFactors = FALSE
  )
} else {
  # Find unique population+MAF combinations with first file as sample
  result <- do.call(rbind, lapply(
    split(valid_files, paste(valid_files$population, valid_files$maf, sep = "_")),
    function(group) {
      data.frame(
        population = group$population[1],
        maf = group$maf[1],
        sample_file = group$file_path[1],
        stringsAsFactors = FALSE
      )
    }
  ))
  row.names(result) <- NULL
}

# Write output (use write.table to avoid quoting header names which can confuse Nextflow)
write.table(result, "marker_sets.csv", sep = ",", row.names = FALSE, quote = FALSE)
cat("Identified", nrow(result), "unique marker sets\n")

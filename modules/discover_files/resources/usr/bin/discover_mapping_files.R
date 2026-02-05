#!/usr/bin/env Rscript
# discover_mapping_files.R - Scan input directory for mapping TSV files
#
# Usage: Rscript discover_mapping_files.R <input_dir>
# Output: mapping_files.csv with columns: file_path, filename, population, maf

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Usage: Rscript discover_mapping_files.R <input_dir>")
}

input_dir <- args[1]

if (!dir.exists(input_dir)) {
  stop(paste("Input directory not found:", input_dir))
}

# Source R modules - R_SOURCE_DIR env var is required (set by Nextflow process script block)
# For standalone usage: R_SOURCE_DIR=./R Rscript discover_mapping_files.R <args>
r_source_dir <- Sys.getenv("R_SOURCE_DIR", unset = "")
if (r_source_dir == "") {
  stop("R_SOURCE_DIR environment variable must be set. Example: R_SOURCE_DIR=./R Rscript discover_mapping_files.R <args>")
}
if (!dir.exists(r_source_dir)) {
  stop(paste("R_SOURCE_DIR does not exist:", r_source_dir))
}

source(file.path(r_source_dir, "utils.R"))

# Find all mapping files
cat("Scanning for mapping files in:", input_dir, "\n")

all_files <- list.files(
  input_dir,
  pattern = "_mapping\\.tsv$",
  recursive = TRUE,
  full.names = TRUE
)

# Exclude reprocessed files
mapping_files <- all_files[!grepl("_reprocessed", all_files)]

cat("Found", length(mapping_files), "mapping files\n")

if (length(mapping_files) == 0) {
  # Write empty output file
  result <- data.frame(
    file_path = character(),
    filename = character(),
    population = character(),
    maf = numeric(),
    stringsAsFactors = FALSE
  )
} else {
  # Parse each filename to extract parameters
  result <- do.call(rbind, lapply(mapping_files, function(fp) {
    params <- parse_mapping_filename(basename(fp))
    if (is.null(params)) {
      data.frame(
        file_path = normalizePath(fp),
        filename = basename(fp),
        population = NA_character_,
        maf = NA_real_,
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        file_path = normalizePath(fp),
        filename = basename(fp),
        population = params$population,
        maf = params$maf,
        stringsAsFactors = FALSE
      )
    }
  }))
}

# Write output (use write.table to avoid quoting header names which can confuse Nextflow)
write.table(result, "mapping_files.csv", sep = ",", row.names = FALSE, quote = FALSE)
cat("Output written to mapping_files.csv\n")

# Report any files that couldn't be parsed
unparseable <- sum(is.na(result$population))
if (unparseable > 0) {
  warning(paste(unparseable, "files could not be parsed"))
}

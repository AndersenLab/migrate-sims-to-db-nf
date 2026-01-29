#!/usr/bin/env Rscript
# discover_qtl_batches.R - Discover (population, algorithm) batches from mapping database
#
# Reads the mapping metadata and generates a CSV of unique (population, algorithm)
# combinations for parallel QTL analysis.
#
# Usage:
#   Rscript discover_qtl_batches.R --mapping_db /path/to/db [--population POP] [--algorithm ALGO]
#
# Output:
#   qtl_batches.csv - CSV with columns: population, algorithm, n_mappings

library(optparse)

# Parse command line arguments
option_list <- list(
  make_option(
    c("-d", "--mapping_db"),
    type = "character",
    default = NULL,
    help = "Path to mapping database directory [required]"
  ),
  make_option(
    c("-p", "--population"),
    type = "character",
    default = NULL,
    help = "Filter to specific population [optional]"
  ),
  make_option(
    c("-a", "--algorithm"),
    type = "character",
    default = NULL,
    help = "Filter to specific algorithm (INBRED or LOCO) [optional]"
  )
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

if (is.null(opt$mapping_db)) {
  stop("Error: --mapping_db is required")
}

# Source R modules - get script directory from commandArgs when run via Rscript
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(sub("^--file=", "", file_arg)))
  }
  # Fallback to current directory
  return(".")
}
script_dir <- get_script_dir()
r_dir <- file.path(dirname(script_dir), "R")

source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "io.R"))
source(file.path(r_dir, "database.R"))
source(file.path(r_dir, "queries.R"))

# Main logic
log_msg("Discovering QTL analysis batches...")
log_msg(glue::glue("  Mapping database: {opt$mapping_db}"))

if (!is.null(opt$population)) {
  log_msg(glue::glue("  Population filter: {opt$population}"))
}
if (!is.null(opt$algorithm)) {
  log_msg(glue::glue("  Algorithm filter: {opt$algorithm}"))
}

# Read mapping metadata
metadata <- get_metadata(opt$mapping_db)
log_msg(glue::glue("Found {nrow(metadata)} total mappings"))

# Apply filters if specified
if (!is.null(opt$population)) {
  metadata <- metadata[metadata$population == opt$population, ]
  log_msg(glue::glue("After population filter: {nrow(metadata)} mappings"))
}

if (!is.null(opt$algorithm)) {
  metadata <- metadata[metadata$algorithm == opt$algorithm, ]
  log_msg(glue::glue("After algorithm filter: {nrow(metadata)} mappings"))
}

if (nrow(metadata) == 0) {
  stop("No mappings found after applying filters")
}

# Group by (population, algorithm) to get batches
batches <- metadata %>%
  dplyr::group_by(population, algorithm) %>%
  dplyr::summarise(n_mappings = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(population, algorithm)

log_msg(glue::glue("Identified {nrow(batches)} batches:"))
for (i in seq_len(nrow(batches))) {
  log_msg(glue::glue(
    "  {batches$population[i]}_{batches$algorithm[i]}: {batches$n_mappings[i]} mappings"
  ))
}

# Write output CSV
output_file <- "qtl_batches.csv"
readr::write_csv(batches, output_file)
log_msg(glue::glue("Wrote batch list to: {output_file}"))

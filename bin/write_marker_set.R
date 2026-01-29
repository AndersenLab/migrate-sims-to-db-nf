#!/usr/bin/env Rscript
# write_marker_set.R - Create marker set from sample mapping file
#
# Usage: Rscript write_marker_set.R <sample_file> <population> <maf> <base_dir> [eigen_lookup.tsv]
# Output: marker set Parquet file in base_dir/markers/

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 4) {
  stop("Usage: Rscript write_marker_set.R <sample_file> <population> <maf> <base_dir> [eigen_lookup.tsv]")
}

sample_file <- args[1]
population <- args[2]
maf <- as.numeric(args[3])
base_dir <- args[4]
eigen_lookup_file <- if (length(args) >= 5) args[5] else NULL

# Source R modules
script_dir <- dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)))
if (length(script_dir) == 0) script_dir <- "."
project_root <- normalizePath(file.path(script_dir, ".."))

source(file.path(project_root, "R/utils.R"))
source(file.path(project_root, "R/io.R"))
source(file.path(project_root, "R/database.R"))

# Initialize database
init_database(base_dir)

# Check if marker set already exists
if (marker_set_exists(population, maf, base_dir)) {
  cat("Marker set already exists:", population, maf, "- skipping\n")
  quit(status = 0)
}

# Read sample file
cat("Reading sample file for marker set:", population, maf, "\n")
df <- read_mapping_file(sample_file, verbose = FALSE)

# Deduplicate
df <- df[!duplicated(df[, c("CHROM", "POS")]), ]

# Look up EIGEN value
n_independent_tests <- NA_real_
eigen_source_file <- NA_character_

if (!is.null(eigen_lookup_file) && file.exists(eigen_lookup_file)) {
  eigen_lookup <- read.table(eigen_lookup_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE)
  key <- paste0(population, "_", maf)
  match_row <- eigen_lookup[eigen_lookup$key == key, ]
  if (nrow(match_row) > 0) {
    n_independent_tests <- match_row$n_independent_tests[1]
    eigen_source_file <- match_row$source_file[1]
    cat("Found EIGEN data:", n_independent_tests, "independent tests\n")
  } else {
    cat("Warning: No EIGEN data found for", key, "\n")
  }
}

# Write marker set
write_marker_set(
  df = df,
  population = population,
  maf = maf,
  base_dir = base_dir,
  overwrite = FALSE,
  n_independent_tests = n_independent_tests,
  eigen_source_file = eigen_source_file
)

cat("Marker set written:", population, maf, "with", nrow(df), "markers\n")

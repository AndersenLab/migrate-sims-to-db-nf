#!/usr/bin/env Rscript
# process_single_mapping.R - Import a single mapping file to partitioned storage
#
# Usage: Rscript process_single_mapping.R <mapping_file> <base_dir>

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop("Usage: Rscript process_single_mapping.R <mapping_file> <base_dir>")
}

mapping_file <- args[1]
base_dir <- args[2]

# Source R modules - R_SOURCE_DIR env var is required (set by Nextflow process script block)
# For standalone usage: R_SOURCE_DIR=./R Rscript process_single_mapping.R <args>
r_source_dir <- Sys.getenv("R_SOURCE_DIR", unset = "")
if (r_source_dir == "") {
  stop("R_SOURCE_DIR environment variable must be set. Example: R_SOURCE_DIR=./R Rscript process_single_mapping.R <args>")
}
if (!dir.exists(r_source_dir)) {
  stop(paste("R_SOURCE_DIR does not exist:", r_source_dir))
}

source(file.path(r_source_dir, "utils.R"))
source(file.path(r_source_dir, "io.R"))
source(file.path(r_source_dir, "database.R"))

# Parse filename
params <- parse_mapping_filename(basename(mapping_file))
if (is.null(params)) {
  stop("Could not parse filename: ", basename(mapping_file))
}

mapping_id <- generate_mapping_id(params)

# Initialize database
init_database(base_dir)

# Read and deduplicate
df <- read_mapping_file(mapping_file, verbose = FALSE)
n_before <- nrow(df)
df <- df[!duplicated(df[, c("CHROM", "POS")]), ]
n_after <- nrow(df)

# Write to partition
write_mapping_partitioned(df, params, base_dir)

cat("Processed:", mapping_id, "(", n_before - n_after, "duplicates removed)\n")

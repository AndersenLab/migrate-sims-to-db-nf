#!/usr/bin/env Rscript
# build_eigen_lookup.R - Build EIGEN lookup table from directory
#
# Usage: Rscript build_eigen_lookup.R <search_dir>
# Output: eigen_lookup.tsv with columns: key, population, maf, n_independent_tests, source_file

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Usage: Rscript build_eigen_lookup.R <search_dir>")
}

search_dir <- args[1]

# Source R modules - R_SOURCE_DIR env var is required (set by Nextflow process script block)
# For standalone usage: R_SOURCE_DIR=./R Rscript build_eigen_lookup.R <args>
r_source_dir <- Sys.getenv("R_SOURCE_DIR", unset = "")
if (r_source_dir == "") {
  stop("R_SOURCE_DIR environment variable must be set. Example: R_SOURCE_DIR=./R Rscript build_eigen_lookup.R <args>")
}
if (!dir.exists(r_source_dir)) {
  stop(paste("R_SOURCE_DIR does not exist:", r_source_dir))
}

source(file.path(r_source_dir, "utils.R"))
source(file.path(r_source_dir, "io.R"))

# Search multiple locations for EIGEN files
search_dirs <- c(
  search_dir,
  file.path(search_dir, "Genotype_Matrix"),
  file.path(dirname(search_dir), "Genotype_Matrix")
)

eigen_lookup <- list()
for (dir in search_dirs) {
  if (dir.exists(dir)) {
    lookup <- build_eigen_lookup(dir)
    if (length(lookup) > 0) {
      eigen_lookup <- lookup
      cat("Found EIGEN data for", length(lookup), "marker sets in:", dir, "\n")
      break
    }
  }
}

if (length(eigen_lookup) == 0) {
  cat("Warning: No EIGEN files found\n")
  # Write empty output
  result <- data.frame(
    key = character(),
    population = character(),
    maf = numeric(),
    n_independent_tests = numeric(),
    source_file = character(),
    stringsAsFactors = FALSE
  )
} else {
  # Convert lookup to dataframe
  result <- do.call(rbind, lapply(names(eigen_lookup), function(key) {
    entry <- eigen_lookup[[key]]
    parts <- strsplit(key, "_(?=[0-9.]+$)", perl = TRUE)[[1]]
    population <- parts[1]
    maf <- as.numeric(parts[2])

    data.frame(
      key = key,
      population = population,
      maf = maf,
      n_independent_tests = entry$n_independent_tests,
      source_file = entry$source_file,
      stringsAsFactors = FALSE
    )
  }))
}

# Write output
write.table(result, "eigen_lookup.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
cat("Output written to eigen_lookup.tsv with", nrow(result), "entries\n")

#!/usr/bin/env Rscript
# analyze_qtl_batch.R - Per-batch QTL analysis
#
# Processes all mappings for a (population, algorithm) batch.
# For each mapping, computes QTL using both BF and EIGEN thresholds (when available).
#
# Usage:
#   Rscript analyze_qtl_batch.R \
#     --population POP \
#     --algorithm ALGO \
#     --mapping_db /path/to/db \
#     --qtl_output /path/to/qtl \
#     --alpha 0.05 \
#     --ci_size 150 \
#     --snp_grouping 1000
#
# Output:
#   {qtl_output}/qtl_regions/{population}_{algorithm}_qtl_regions.parquet
#   {qtl_output}/analysis_summary_{population}_{algorithm}.parquet
#   qtl_batch_complete_{population}_{algorithm}.txt

library(optparse)
library(dplyr)

# Parse command line arguments
option_list <- list(
  make_option(
    c("-p", "--population"),
    type = "character",
    default = NULL,
    help = "Population identifier [required]"
  ),
  make_option(
    c("-a", "--algorithm"),
    type = "character",
    default = NULL,
    help = "Algorithm (INBRED or LOCO) [required]"
  ),
  make_option(
    c("-d", "--mapping_db"),
    type = "character",
    default = NULL,
    help = "Path to mapping database directory [required]"
  ),
  make_option(
    c("-o", "--qtl_output"),
    type = "character",
    default = NULL,
    help = "Path to QTL output directory [required]"
  ),
  make_option(
    c("--alpha"),
    type = "double",
    default = 0.05,
    help = "Significance level [default: 0.05]"
  ),
  make_option(
    c("--ci_size"),
    type = "integer",
    default = 150,
    help = "CI size (markers left/right of peak) [default: 150]"
  ),
  make_option(
    c("--snp_grouping"),
    type = "integer",
    default = 1000,
    help = "SNP grouping distance [default: 1000]"
  )
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

# Validate required arguments
if (is.null(opt$population)) stop("Error: --population is required")
if (is.null(opt$algorithm)) stop("Error: --algorithm is required")
if (is.null(opt$mapping_db)) stop("Error: --mapping_db is required")
if (is.null(opt$qtl_output)) stop("Error: --qtl_output is required")

# Source R modules - R_SOURCE_DIR env var is required (set by Nextflow process script block)
# For standalone usage: R_SOURCE_DIR=./R Rscript analyze_qtl_batch.R <args>
r_source_dir <- Sys.getenv("R_SOURCE_DIR", unset = "")
if (r_source_dir == "") {
  stop("R_SOURCE_DIR environment variable must be set. Example: R_SOURCE_DIR=./R Rscript analyze_qtl_batch.R <args>")
}
if (!dir.exists(r_source_dir)) {
  stop(paste("R_SOURCE_DIR does not exist:", r_source_dir))
}

source(file.path(r_source_dir, "utils.R"))
source(file.path(r_source_dir, "io.R"))
source(file.path(r_source_dir, "database.R"))
source(file.path(r_source_dir, "queries.R"))
source(file.path(r_source_dir, "analysis.R"))
source(file.path(r_source_dir, "qtl_database.R"))

# Main logic
population <- opt$population
algorithm <- opt$algorithm
mapping_db <- opt$mapping_db
qtl_output <- opt$qtl_output
alpha <- opt$alpha
ci_size <- opt$ci_size
snp_grouping <- opt$snp_grouping

log_msg(paste0("=", strrep("=", 60)))
log_msg(glue::glue("QTL Analysis: {population}_{algorithm}"))
log_msg(paste0("=", strrep("=", 60)))
log_msg(glue::glue("  Mapping database: {mapping_db}"))
log_msg(glue::glue("  QTL output: {qtl_output}"))
log_msg(glue::glue("  Alpha: {alpha}"))
log_msg(glue::glue("  CI size: {ci_size}"))
log_msg(glue::glue("  SNP grouping: {snp_grouping}"))

# Initialize QTL database
init_qtl_database(qtl_output)

# Get mappings for this batch
metadata <- get_metadata(mapping_db) %>%
  filter(population == !!population, algorithm == !!algorithm)

n_mappings <- nrow(metadata)
log_msg(glue::glue("Found {n_mappings} mappings to process"))

if (n_mappings == 0) {
  stop(glue::glue("No mappings found for {population}_{algorithm}"))
}

# Accumulators for results
all_qtl_regions <- list()
all_summaries <- list()

# Process each mapping
for (i in seq_len(n_mappings)) {
  mapping_id <- metadata$mapping_id[i]
  maf <- metadata$maf[i]

  if (i %% 10 == 1 || i == n_mappings) {
    log_msg(glue::glue("Processing mapping {i}/{n_mappings}: {mapping_id}"))
  }

  # Get mapping data
  mapping_data <- tryCatch(
    query_for_threshold_analysis(mapping_id, mapping_db),
    error = function(e) {
      log_msg(glue::glue("Error querying {mapping_id}: {e$message}"), level = "WARN")
      return(NULL)
    }
  )

  if (is.null(mapping_data) || nrow(mapping_data) == 0) {
    log_msg(glue::glue("Skipping {mapping_id}: no data"), level = "WARN")
    next
  }

  # Get threshold parameters
  params <- tryCatch(
    get_threshold_params(population, maf, alpha, mapping_db),
    error = function(e) {
      log_msg(glue::glue("Error getting params for {mapping_id}: {e$message}"), level = "WARN")
      return(NULL)
    }
  )

  if (is.null(params)) {
    next
  }

  # ========================================
  # BF Threshold Analysis (always)
  # ========================================
  bf_thresh <- calculate_threshold("BF", n_markers = params$n_markers, alpha = alpha)

  bf_processed <- analyze_mapping(
    df = mapping_data,
    threshold_value = bf_thresh$threshold_value,
    threshold_method = "BF",
    ci_size = ci_size,
    snp_grouping = snp_grouping,
    verbose = FALSE
  )

  bf_qtl <- extract_qtl_regions(bf_processed)
  bf_summary <- summarize_detection(bf_processed)

  # Add metadata columns to QTL regions
 if (nrow(bf_qtl) > 0) {
    bf_qtl <- bf_qtl %>%
      rename(threshold_method = sig_threshold_method) %>%
      mutate(
        mapping_id = mapping_id,
        population = population,
        maf = maf,
        algorithm = algorithm,
        ci_size = ci_size,
        snp_grouping = snp_grouping
      )
    all_qtl_regions <- c(all_qtl_regions, list(bf_qtl))
  }

  # Add metadata columns to summary
  bf_summary_df <- data.frame(
    mapping_id = mapping_id,
    threshold_method = "BF",
    population = population,
    maf = maf,
    algorithm = algorithm,
    n_markers = bf_summary$n_markers,
    n_significant = bf_summary$n_significant,
    pct_significant = bf_summary$pct_significant,
    n_qtl = bf_summary$n_qtl,
    max_log10p = bf_summary$max_log10p,
    threshold_value = bf_summary$threshold_value,
    ci_size = ci_size,
    snp_grouping = snp_grouping,
    stringsAsFactors = FALSE
  )
  all_summaries <- c(all_summaries, list(bf_summary_df))

  # ========================================
  # EIGEN Threshold Analysis (if available)
  # ========================================
  if (!is.na(params$n_independent_tests) && params$n_independent_tests > 0) {
    eigen_thresh <- calculate_threshold("EIGEN", n_independent = params$n_independent_tests, alpha = alpha)

    eigen_processed <- analyze_mapping(
      df = mapping_data,
      threshold_value = eigen_thresh$threshold_value,
      threshold_method = "EIGEN",
      ci_size = ci_size,
      snp_grouping = snp_grouping,
      verbose = FALSE
    )

    eigen_qtl <- extract_qtl_regions(eigen_processed)
    eigen_summary <- summarize_detection(eigen_processed)

    # Add metadata columns to QTL regions
    if (nrow(eigen_qtl) > 0) {
      eigen_qtl <- eigen_qtl %>%
        rename(threshold_method = sig_threshold_method) %>%
        mutate(
          mapping_id = mapping_id,
          population = population,
          maf = maf,
          algorithm = algorithm,
          ci_size = ci_size,
          snp_grouping = snp_grouping
        )
      all_qtl_regions <- c(all_qtl_regions, list(eigen_qtl))
    }

    # Add metadata columns to summary
    eigen_summary_df <- data.frame(
      mapping_id = mapping_id,
      threshold_method = "EIGEN",
      population = population,
      maf = maf,
      algorithm = algorithm,
      n_markers = eigen_summary$n_markers,
      n_significant = eigen_summary$n_significant,
      pct_significant = eigen_summary$pct_significant,
      n_qtl = eigen_summary$n_qtl,
      max_log10p = eigen_summary$max_log10p,
      threshold_value = eigen_summary$threshold_value,
      ci_size = ci_size,
      snp_grouping = snp_grouping,
      stringsAsFactors = FALSE
    )
    all_summaries <- c(all_summaries, list(eigen_summary_df))
  }
}

# Combine and write results
log_msg("Writing results...")

# QTL regions
if (length(all_qtl_regions) > 0) {
  combined_qtl <- bind_rows(all_qtl_regions)
  write_qtl_regions(combined_qtl, population, algorithm, qtl_output)
} else {
  log_msg("No QTL regions found for this batch")
  # Write empty file to signal completion
  combined_qtl <- data.frame()
  write_qtl_regions(combined_qtl, population, algorithm, qtl_output)
}

# Summary
if (length(all_summaries) > 0) {
  combined_summary <- bind_rows(all_summaries)
  write_analysis_summary_batch(combined_summary, population, algorithm, qtl_output)
} else {
  log_msg("No summary data for this batch")
}

# Write completion signal
completion_file <- glue::glue("qtl_batch_complete_{population}_{algorithm}.txt")
writeLines(
  c(
    glue::glue("Batch: {population}_{algorithm}"),
    glue::glue("Mappings processed: {n_mappings}"),
    glue::glue("QTL regions: {if (length(all_qtl_regions) > 0) nrow(combined_qtl) else 0}"),
    glue::glue("Completed: {Sys.time()}")
  ),
  completion_file
)

# Summary statistics
n_bf_qtl <- sum(sapply(all_summaries, function(x) {
  if (x$threshold_method == "BF") x$n_qtl else 0
}))
n_eigen_qtl <- sum(sapply(all_summaries, function(x) {
  if (x$threshold_method == "EIGEN") x$n_qtl else 0
}))

log_msg(paste0("=", strrep("=", 60)))
log_msg(glue::glue("Batch complete: {population}_{algorithm}"))
log_msg(glue::glue("  Mappings processed: {n_mappings}"))
log_msg(glue::glue("  QTL (BF threshold): {n_bf_qtl}"))
log_msg(glue::glue("  QTL (EIGEN threshold): {n_eigen_qtl}"))
log_msg(paste0("=", strrep("=", 60)))

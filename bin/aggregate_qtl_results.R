#!/usr/bin/env Rscript
# aggregate_qtl_results.R - Aggregate QTL analysis results
#
# Merges per-batch summary files into a single analysis_summary.parquet
# and creates analysis_metadata.parquet with run parameters.
#
# Usage:
#   Rscript aggregate_qtl_results.R \
#     --qtl_dir /path/to/qtl \
#     --alpha 0.05 \
#     --ci_size 150 \
#     --snp_grouping 1000
#
# Output:
#   {qtl_dir}/analysis_summary.parquet (merged from batch files)
#   {qtl_dir}/analysis_metadata.parquet
#   qtl_analysis_summary.txt

library(optparse)
library(dplyr)

# Parse command line arguments
option_list <- list(
  make_option(
    c("-d", "--qtl_dir"),
    type = "character",
    default = NULL,
    help = "Path to QTL output directory [required]"
  ),
  make_option(
    c("--alpha"),
    type = "double",
    default = 0.05,
    help = "Significance level used [default: 0.05]"
  ),
  make_option(
    c("--ci_size"),
    type = "integer",
    default = 150,
    help = "CI size used [default: 150]"
  ),
  make_option(
    c("--snp_grouping"),
    type = "integer",
    default = 1000,
    help = "SNP grouping used [default: 1000]"
  )
)

opt_parser <- OptionParser(option_list = option_list)
opt <- parse_args(opt_parser)

if (is.null(opt$qtl_dir)) {
  stop("Error: --qtl_dir is required")
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
source(file.path(r_dir, "qtl_database.R"))

# Main logic
qtl_dir <- opt$qtl_dir
alpha <- opt$alpha
ci_size <- opt$ci_size
snp_grouping <- opt$snp_grouping

log_msg(paste0("=", strrep("=", 60)))
log_msg("Aggregating QTL Analysis Results")
log_msg(paste0("=", strrep("=", 60)))
log_msg(glue::glue("  QTL directory: {qtl_dir}"))
log_msg(glue::glue("  Parameters: alpha={alpha}, ci_size={ci_size}, snp_grouping={snp_grouping}"))

# Merge batch summary files
merge_analysis_summaries(qtl_dir)

# Read merged summary for statistics
summary_df <- read_analysis_summary(qtl_dir)

if (nrow(summary_df) == 0) {
  log_msg("Warning: No summary data found", level = "WARN")
  n_populations <- 0
  n_mappings <- 0
  n_qtl_bf <- 0
  n_qtl_eigen <- 0
} else {
  n_populations <- length(unique(summary_df$population))
  n_mappings <- length(unique(summary_df$mapping_id))

  bf_summary <- summary_df %>% filter(threshold_method == "BF")
  eigen_summary <- summary_df %>% filter(threshold_method == "EIGEN")

  n_qtl_bf <- sum(bf_summary$n_qtl, na.rm = TRUE)
  n_qtl_eigen <- sum(eigen_summary$n_qtl, na.rm = TRUE)
}

# Write analysis metadata
write_analysis_metadata(
  alpha = alpha,
  ci_size = ci_size,
  snp_grouping = snp_grouping,
  n_populations = n_populations,
  n_mappings = n_mappings,
  n_qtl_bf = n_qtl_bf,
  n_qtl_eigen = n_qtl_eigen,
  qtl_dir = qtl_dir
)

# Get QTL database statistics
stats <- qtl_db_stats(qtl_dir)

# Write human-readable summary
summary_text <- c(
  paste0("=", strrep("=", 60)),
  "QTL Analysis Summary",
  paste0("=", strrep("=", 60)),
  "",
  "Parameters:",
  glue::glue("  Alpha: {alpha}"),
  glue::glue("  CI size: {ci_size}"),
  glue::glue("  SNP grouping: {snp_grouping}"),
  "",
  "Results:",
  glue::glue("  Populations: {n_populations}"),
  glue::glue("  Mappings analyzed: {n_mappings}"),
  glue::glue("  QTL files: {stats$n_qtl_files}"),
  glue::glue("  Total QTL regions: {stats$n_qtl_regions}"),
  "",
  "By Threshold Method:",
  glue::glue("  BF threshold: {n_qtl_bf} QTL"),
  glue::glue("  EIGEN threshold: {n_qtl_eigen} QTL"),
  "",
  glue::glue("Completed: {Sys.time()}"),
  paste0("=", strrep("=", 60))
)

# Write summary file
summary_file <- "qtl_analysis_summary.txt"
writeLines(summary_text, summary_file)
log_msg(glue::glue("Wrote summary to: {summary_file}"))

# Print to console
cat(paste(summary_text, collapse = "\n"), "\n")

# Also print detection rate summary if we have data
if (nrow(summary_df) > 0) {
  cat("\nDetection Rate Summary:\n")

  detection_summary <- summary_df %>%
    group_by(algorithm, threshold_method) %>%
    summarise(
      n_mappings = n(),
      mean_qtl = round(mean(n_qtl, na.rm = TRUE), 2),
      detection_rate = round(mean(n_qtl > 0, na.rm = TRUE) * 100, 1),
      .groups = "drop"
    )

  print(detection_summary)
}

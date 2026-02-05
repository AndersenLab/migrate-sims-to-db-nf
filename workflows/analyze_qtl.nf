#!/usr/bin/env nextflow
/*
 * analyze_qtl.nf - Standalone QTL Analysis Workflow
 *
 * Re-runs QTL analysis on an existing mapping database with different parameters.
 * Use this to explore different CI sizes or SNP grouping distances.
 *
 * IMPORTANT: Must be run from the project root directory, or with explicit
 * config to enable module binaries:
 *   nextflow run workflows/analyze_qtl.nf -c nextflow.config --mapping_db /path/to/db
 *
 * Usage:
 *   cd migrate-to-db-nf
 *   nextflow run workflows/analyze_qtl.nf \
 *       --mapping_db /path/to/existing/db \
 *       --output /path/to/qtl_output \
 *       --ci_size 200 \
 *       --snp_grouping 500
 */

nextflow.enable.dsl = 2

// Include modules
include { DISCOVER_QTL_BATCHES } from '../modules/discover_qtl_batches/main'
include { ANALYZE_QTL_BATCH } from '../modules/analyze_qtl_batch/main'
include { AGGREGATE_QTL_RESULTS } from '../modules/aggregate_qtl_results/main'


/*
 * Print pipeline info
 */
log.info """
=======================================================
  QTL Analysis Workflow (Standalone)
=======================================================
Mapping database : ${params.mapping_db ?: 'NOT SET'}
Output directory : ${params.output ?: params.qtl_output ?: './results/qtl'}
Population filter: ${params.population ?: 'all'}
Algorithm filter : ${params.algorithm ?: 'all'}
-------------------------------------------------------
Analysis Parameters:
  Alpha          : ${params.alpha}
  CI size        : ${params.ci_size}
  SNP grouping   : ${params.snp_grouping}
-------------------------------------------------------
"""


/*
 * Validate parameters
 */
if (!params.mapping_db) {
    error "Error: --mapping_db is required. Specify the path to an existing mapping database."
}


/*
 * Main workflow
 */
workflow {

    // Resolve paths
    mapping_db = file(params.mapping_db, checkIfExists: true)
    qtl_output = params.qtl_output ?: (params.output ?: file(params.mapping_db).toAbsolutePath().toString() + "/qtl")

    // Ensure qtl_output is absolute
    if (!qtl_output.startsWith("/")) {
        qtl_output = file(qtl_output).toAbsolutePath().toString()
    }

    log.info "QTL output directory: ${qtl_output}"

    // Handle null filter values (convert to empty string for Nextflow)
    def population_filter = params.population ?: ""
    def algorithm_filter = params.algorithm ?: ""

    // Phase 1: Discover batches
    // =========================
    DISCOVER_QTL_BATCHES(
        mapping_db,
        population_filter,
        algorithm_filter
    )


    // Phase 2: Analyze each batch in parallel
    // =======================================
    ch_batches = DISCOVER_QTL_BATCHES.out.batches
        .splitCsv(header: true)
        .map { row -> tuple(row.population, row.algorithm) }

    ANALYZE_QTL_BATCH(
        ch_batches,
        mapping_db,
        qtl_output,
        params.alpha,
        params.ci_size,
        params.snp_grouping
    )


    // Phase 3: Aggregate results
    // ==========================
    AGGREGATE_QTL_RESULTS(
        ANALYZE_QTL_BATCH.out.done.collect(),
        qtl_output,
        params.alpha,
        params.ci_size,
        params.snp_grouping
    )
}


/*
 * Completion handler
 */
workflow.onComplete {
    log.info """
=======================================================
QTL Analysis Complete
=======================================================
Completed at : ${workflow.complete}
Duration     : ${workflow.duration}
Success      : ${workflow.success}
Exit status  : ${workflow.exitStatus}
Output dir   : ${params.qtl_output ?: params.output ?: 'default'}
=======================================================
"""
}


/*
 * Error handler
 */
workflow.onError {
    log.error "Pipeline execution stopped with error: ${workflow.errorMessage}"
}

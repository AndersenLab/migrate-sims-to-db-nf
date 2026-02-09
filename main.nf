#!/usr/bin/env nextflow
/*
 * migrate-to-db-nf: Import GWAS mapping TSV files to Parquet database
 *
 * Pipeline Architecture:
 *   Phase 1: Discovery
 *   DISCOVER_FILES -> BUILD_EIGEN_LOOKUP -> IDENTIFY_MARKER_SETS
 *          |                  |                    |
 *          v                  v                    v
 *      mapping_files     eigen_lookup         marker_sets
 *
 *   Phase 2: Pre-create marker sets
 *          |                  +--------------------+
 *          |                  |
 *          v                  v
 *   WRITE_MARKER_SETS (parallel per marker set)
 *
 *   Phase 3: Process mappings
 *          |
 *          v
 *   PROCESS_MAPPINGS (parallel per file)
 *
 *   Phase 4: Aggregate results
 *          |
 *          v
 *   AGGREGATE_METADATA
 *
 *   Phase 5: QTL Analysis (optional, --analyze_qtl)
 *          |
 *          v
 *   DISCOVER_QTL_BATCHES -> ANALYZE_QTL_BATCH -> AGGREGATE_QTL_RESULTS
 *                         (parallel per pop/algo)
 */

nextflow.enable.dsl = 2

// Include modules
include { DISCOVER_MAPPING_FILES } from './modules/discover_files/main'
include { BUILD_EIGEN_LOOKUP } from './modules/build_eigen_lookup/main'
include { IDENTIFY_MARKER_SETS } from './modules/identify_marker_sets/main'
include { PROCESS_MAPPING } from './modules/process_mapping/main'
include { WRITE_MARKER_SET } from './modules/write_marker_set/main'
include { AGGREGATE_METADATA } from './modules/aggregate_metadata/main'

// QTL analysis modules (optional Phase 5)
include { DISCOVER_QTL_BATCHES } from './modules/discover_qtl_batches/main'
include { ANALYZE_QTL_BATCH } from './modules/analyze_qtl_batch/main'
include { AGGREGATE_QTL_RESULTS } from './modules/aggregate_qtl_results/main'


/*
 * Print pipeline info
 */
// Build QTL info string
def qtl_info = params.analyze_qtl ? """
QTL Analysis     : enabled
  Alpha          : ${params.alpha}
  CI size        : ${params.ci_size}
  SNP grouping   : ${params.snp_grouping}
  QTL output     : ${params.qtl_output ?: '${output}/qtl'}""" : """
QTL Analysis     : disabled (use --analyze_qtl to enable)"""

log.info """
=======================================================
  migrate-to-db-nf  v${workflow.manifest.version}
=======================================================
Input directory  : ${params.input}
EIGEN directory  : ${params.eigen_dir ?: 'auto-detect'}
Output directory : ${params.output}
Overwrite        : ${params.overwrite}
${qtl_info}
-------------------------------------------------------
"""


/*
 * Validate parameters
 */
if (!params.input) {
    error "Error: --input parameter is required. Specify the directory containing mapping TSV files."
}

/*
 * Main workflow
 */
workflow {

    // Validate and resolve paths
    input_dir = file(params.input, checkIfExists: true)
    output_dir = file(params.output).toAbsolutePath().toString()

    // Phase 1: Discovery
    // ==================

    // Discover mapping files
    DISCOVER_MAPPING_FILES(input_dir)

    // Build EIGEN lookup (search input dir and Genotype_Matrix subdirs)
    eigen_search_dir = params.eigen_dir ? file(params.eigen_dir) : input_dir
    BUILD_EIGEN_LOOKUP(eigen_search_dir)

    // Identify unique marker sets
    IDENTIFY_MARKER_SETS(DISCOVER_MAPPING_FILES.out.mapping_files)


    // Phase 2: Pre-create marker sets
    // ================================

    // Parse marker_sets.csv to create channel of (population, maf, sample_file) tuples
    ch_marker_sets = IDENTIFY_MARKER_SETS.out.marker_sets
        .splitCsv(header: true)
        .map { row ->
            tuple(row.population, row.maf, file(row.sample_file))
        }

    // Write marker sets (one per unique population+MAF)
    WRITE_MARKER_SET(
        ch_marker_sets,
        BUILD_EIGEN_LOOKUP.out.eigen_lookup,
        output_dir
    )


    // Phase 3: Process mappings in parallel
    // ======================================

    // Parse mapping_files.csv to create channel of file paths
    ch_mapping_files = DISCOVER_MAPPING_FILES.out.mapping_files
        .splitCsv(header: true)
        .filter { row -> row.population != null && row.population != '' && row.population != 'NA' }
        .map { row -> file(row.file_path) }

    // Wait for marker sets to be written before processing mappings
    // This ensures the database structure exists
    ch_mapping_files_ready = ch_mapping_files
        .combine(WRITE_MARKER_SET.out.marker_set_id.collect().map { it -> true })
        .map { it[0] }

    // Process each mapping file
    PROCESS_MAPPING(
        ch_mapping_files_ready,
        output_dir
    )


    // Phase 4: Aggregate results
    // ==========================

    // Build metadata by scanning parquet files after all mappings complete
    AGGREGATE_METADATA(
        PROCESS_MAPPING.out.done.collect(),
        output_dir
    )


    // Phase 5: QTL Analysis (optional)
    // =================================
    // Enabled with --analyze_qtl flag
    // Can also be run independently via workflows/analyze_qtl.nf

    if (params.analyze_qtl) {
        // Determine QTL output directory
        qtl_output = params.qtl_output ?: "${output_dir}/qtl"

        // Handle null filter values (convert to empty string for Nextflow)
        def population_filter = params.population ?: ""
        def algorithm_filter = params.algorithm ?: ""

        // Wait for database population before discovering batches
        // Use AGGREGATE_METADATA.out.summary as trigger to ensure migration is complete
        ch_db_ready = AGGREGATE_METADATA.out.summary
            .map { summary -> file(output_dir) }

        // Discover (population, algorithm) batches from the mapping database
        DISCOVER_QTL_BATCHES(
            ch_db_ready,
            population_filter,
            algorithm_filter
        )

        // Process batches
        ch_batches = DISCOVER_QTL_BATCHES.out.batches
            .splitCsv(header: true)
            .map { row -> tuple(row.population, row.algorithm) }

        // Run QTL analysis for each (population, algorithm) batch
        ANALYZE_QTL_BATCH(
            ch_batches,
            file(output_dir),
            qtl_output,
            params.alpha,
            params.ci_size,
            params.snp_grouping
        )

        // Aggregate QTL results from all batches
        AGGREGATE_QTL_RESULTS(
            ANALYZE_QTL_BATCH.out.done.collect(),
            qtl_output,
            params.alpha,
            params.ci_size,
            params.snp_grouping
        )
    }
}


/*
 * Completion handler
 */
workflow.onComplete {
    def qtl_summary = params.analyze_qtl ? """
QTL analysis : enabled
QTL output   : ${params.qtl_output ?: params.output + '/qtl'}""" : ""

    log.info """
=======================================================
Pipeline execution summary
=======================================================
Completed at : ${workflow.complete}
Duration     : ${workflow.duration}
Success      : ${workflow.success}
Exit status  : ${workflow.exitStatus}
Work dir     : ${workflow.workDir}
Output dir   : ${params.output}${qtl_summary}
=======================================================
"""
}


/*
 * Error handler
 */
workflow.onError {
    log.error "Pipeline execution stopped with error: ${workflow.errorMessage}"
}

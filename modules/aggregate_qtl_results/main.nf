/*
 * AGGREGATE_QTL_RESULTS
 *
 * Aggregates per-batch QTL results into final summary files.
 */

process AGGREGATE_QTL_RESULTS {
    label 'low_memory'
    tag "aggregate"

    publishDir "${qtl_output}", mode: 'copy', pattern: "qtl_analysis_summary.txt"

    input:
    path completion_signals  // Collected from all batches
    val qtl_output
    val alpha
    val ci_size
    val snp_grouping

    output:
    path "qtl_analysis_summary.txt", emit: summary

    script:
    """
    Rscript ${projectDir}/bin/aggregate_qtl_results.R \
        --qtl_dir '${qtl_output}' \
        --alpha ${alpha} \
        --ci_size ${ci_size} \
        --snp_grouping ${snp_grouping}
    """
}

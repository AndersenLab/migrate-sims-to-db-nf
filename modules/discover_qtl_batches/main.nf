/*
 * DISCOVER_QTL_BATCHES
 *
 * Discovers unique (population, algorithm) batches from mapping database
 * for parallel QTL analysis.
 */

process DISCOVER_QTL_BATCHES {
    label 'local_process'
    tag "discover_batches"

    input:
    path mapping_db
    val population_filter
    val algorithm_filter

    output:
    path "qtl_batches.csv", emit: batches

    script:
    def pop_arg = (population_filter && population_filter != "") ? "--population '${population_filter}'" : ""
    def algo_arg = (algorithm_filter && algorithm_filter != "") ? "--algorithm '${algorithm_filter}'" : ""
    """
    Rscript ${projectDir}/bin/discover_qtl_batches.R \
        --mapping_db ${mapping_db} \
        ${pop_arg} \
        ${algo_arg}
    """
}

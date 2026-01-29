/*
 * ANALYZE_QTL_BATCH
 *
 * Processes all mappings for a (population, algorithm) batch.
 * Computes QTL using both BF and EIGEN thresholds.
 */

process ANALYZE_QTL_BATCH {
    label 'high_memory'
    tag "${population}_${algorithm}"

    input:
    tuple val(population), val(algorithm)
    path mapping_db
    val qtl_output
    val alpha
    val ci_size
    val snp_grouping

    output:
    path "qtl_batch_complete_${population}_${algorithm}.txt", emit: done

    script:
    """
    Rscript ${projectDir}/bin/analyze_qtl_batch.R \
        --population '${population}' \
        --algorithm '${algorithm}' \
        --mapping_db ${mapping_db} \
        --qtl_output '${qtl_output}' \
        --alpha ${alpha} \
        --ci_size ${ci_size} \
        --snp_grouping ${snp_grouping}
    """
}

/*
 * AGGREGATE_METADATA - Scan parquet files and write metadata table
 */

process AGGREGATE_METADATA {
    label 'low_memory'
    tag "aggregate"

    publishDir "${params.output}", mode: 'copy'

    input:
    val ready
    val base_dir

    output:
    path "aggregation_summary.txt", emit: summary

    script:
    """
    export R_SOURCE_DIR="${projectDir}/R"
    aggregate_metadata.R ${base_dir}
    """

    stub:
    """
    echo "Aggregation stub" > aggregation_summary.txt
    """
}

/*
 * IDENTIFY_MARKER_SETS - Find unique population+MAF combinations
 */

process IDENTIFY_MARKER_SETS {
    label 'local_process'
    tag "marker_sets"

    input:
    path mapping_files_csv

    output:
    path "marker_sets.csv", emit: marker_sets

    script:
    """
    Rscript --vanilla ${projectDir}/bin/identify_marker_sets.R ${mapping_files_csv}
    """

    stub:
    """
    echo "population,maf,sample_file" > marker_sets.csv
    """
}

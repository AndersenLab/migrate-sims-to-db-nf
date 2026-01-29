/*
 * PROCESS_MAPPING - Import a single mapping file to partitioned storage
 */

process PROCESS_MAPPING {
    label 'low_memory'
    tag "${mapping_file.baseName}"

    input:
    path mapping_file
    val base_dir

    output:
    val true, emit: done

    script:
    """
    Rscript --vanilla ${projectDir}/bin/process_single_mapping.R ${mapping_file} ${base_dir}
    """

    stub:
    """
    echo "Stub: processed ${mapping_file.name}"
    """
}

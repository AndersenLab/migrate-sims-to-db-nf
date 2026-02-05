/*
 * WRITE_MARKER_SET - Create marker set from sample mapping file
 */

process WRITE_MARKER_SET {
    label 'medium_memory'
    tag "${population}_${maf}"

    input:
    tuple val(population), val(maf), path(sample_file)
    path eigen_lookup
    val base_dir

    output:
    tuple val(population), val(maf), emit: marker_set_id

    script:
    """
    export R_SOURCE_DIR="${projectDir}/R"
    write_marker_set.R \\
        ${sample_file} \\
        ${population} \\
        ${maf} \\
        ${base_dir} \\
        ${eigen_lookup}
    """

    stub:
    """
    echo "Marker set created: ${population}_${maf}"
    """
}

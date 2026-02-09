/*
 * DISCOVER_MAPPING_FILES - Scan input directory for mapping files
 */

process DISCOVER_MAPPING_FILES {
    label 'discovery_process'
    tag "discover"

    input:
    path input_dir

    output:
    path "mapping_files.csv", emit: mapping_files

    script:
    """
    export R_SOURCE_DIR="${projectDir}/R"
    discover_mapping_files.R ${input_dir}
    """

    stub:
    """
    echo "file_path,filename,population,maf" > mapping_files.csv
    """
}

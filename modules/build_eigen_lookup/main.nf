/*
 * BUILD_EIGEN_LOOKUP - Build EIGEN lookup table from directory
 */

process BUILD_EIGEN_LOOKUP {
    label 'discovery_process'
    tag "eigen_lookup"

    input:
    path search_dir

    output:
    path "eigen_lookup.tsv", emit: eigen_lookup

    script:
    """
    export R_SOURCE_DIR="${projectDir}/R"
    build_eigen_lookup.R ${search_dir}
    """

    stub:
    """
    echo -e "key\\tpopulation\\tmaf\\tn_independent_tests\\tsource_file" > eigen_lookup.tsv
    """
}

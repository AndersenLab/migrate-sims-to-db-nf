/*
 * BUILD_EIGEN_LOOKUP - Build EIGEN lookup table from directory
 */

process BUILD_EIGEN_LOOKUP {
    label 'local_process'
    tag "eigen_lookup"

    input:
    path search_dir

    output:
    path "eigen_lookup.tsv", emit: eigen_lookup

    script:
    """
    Rscript --vanilla ${projectDir}/bin/build_eigen_lookup.R ${search_dir}
    """

    stub:
    """
    echo -e "key\\tpopulation\\tmaf\\tn_independent_tests\\tsource_file" > eigen_lookup.tsv
    """
}

process NCBI_FCS_GX_SETUP_SAMPLE {
    tag "${asm_tag}"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:20.04':
        'nf-core/ubuntu:20.04' }"

    input:
    tuple val(asm_tag), path(fasta_file)

    output:
    path 'fasta.file.for.*.fasta'   , emit: fsata
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Exit if running this module with -profile conda / -profile mamba
    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        error "NCBI_FCS_GX_SETUP_SAMPLE module does not support Conda. Please use Docker / Singularity / Podman instead."
    }
    """
    cp $fasta_file fasta.file.for.${asm_tag}.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ubuntu: \$(cat /etc/issue | tr -d 'Ubuntu LTS[:space:]\\\\')
    END_VERSIONS
    """
}

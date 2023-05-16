nextflow.enable.dsl=2

include { ALIGN_READS_TO_FASTA  } from './align_reads_to_fasta.nf'
include { CREATE_HIC_FILE       } from './create_hic_file.nf'

include { HIC_QC                } from '../modules/hic_qc.nf'

workflow HIC_CONTACT_MAP {
    take:
        hic_contact_map_inputs // [tag, assembly_fasta, sample_id, [R1, R2]]
    
    main:
        if (!params.hic.skip) {

            hic_contact_map_inputs
            | map {
                ["${it[2]}.on.${it[0]}", it[1]] // [sample_id.on.tag, assembly_fasta]
            }
            | set { ch_assembly_fasta }


            ALIGN_READS_TO_FASTA(hic_contact_map_inputs)
            | HIC_QC

            ch_assembly_fasta
            | join(ALIGN_READS_TO_FASTA.out.alignment_bam) // [sample_id.on.tag, assembly_fasta, alignment_bam]
            | CREATE_HIC_FILE
            | HIC2_HTML
            | collect
            | set { ch_list_of_html_files }
        } else {
            ch_list_of_html_files = Channel.of([])
        }

    emit:
        list_of_html_files = ch_list_of_html_files
}

process HIC2_HTML {
    tag "$sample_id_on_tag"
    conda 'assembly-qc-conda-env.yml'
    publishDir "${params.outdir.main}/hic", mode: 'copy'

    input:
        tuple val(sample_id_on_tag), path(hic_file)

    output:
        path "*.html"

    script:
        results_folder = file("${params.outdir.main}", checkIfExists: false)
        """
        file_name="$hic_file"
        hic_2_html_943e0fb.py "$params.hic.storage_server" "$results_folder" "$hic_file" > "\${file_name%.*}.html"
        """
}
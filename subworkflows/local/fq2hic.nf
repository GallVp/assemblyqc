include { FASTQ_TRIM_FASTP_FASTQC   } from '../nf-core/fastq_trim_fastp_fastqc/main'
include { FASTQ_BWA_MEM_SAMBLASTER  } from '../pfr/fastq_bwa_mem_samblaster/main'
include { HICQC                     } from '../../modules/local/hicqc'
include { MAKEAGPFROMFASTA          } from '../../modules/local/makeagpfromfasta'
include { AGP2ASSEMBLY              } from '../../modules/local/agp2assembly'
include { ASSEMBLY2BEDPE            } from '../../modules/local/assembly2bedpe'
include { MATLOCK_BAM2_JUICER       } from '../../modules/local/matlock_bam2_juicer'
include { JUICER_SORT               } from '../../modules/local/juicer_sort'
include { RUNASSEMBLYVISUALIZER     } from '../../modules/local/runassemblyvisualizer'
include { HIC2HTML                  } from '../../modules/local/hic2html'

workflow FQ2HIC {
    take:
    reads                           // [ val(meta), [ fq ] ]
    ref                             // [ val(meta2), fa ]
    hic_skip_fastp                  // val: true|false
    hic_skip_fastqc                 // val: true|false

    main:
    ch_versions                     = Channel.empty()

    // SUBWORKFLOW: FASTQ_TRIM_FASTP_FASTQC
    FASTQ_TRIM_FASTP_FASTQC(
        reads,
        [],
        true,                       // val_save_trimmed_fail
        false,                      // val_save_merged
        hic_skip_fastp,
        hic_skip_fastqc
    )

    ch_trim_reads                   = FASTQ_TRIM_FASTP_FASTQC.out.reads
    ch_versions                     = ch_versions.mix(FASTQ_TRIM_FASTP_FASTQC.out.versions)

    // SUBWORKFLOW: FASTQ_BWA_MEM_SAMBLASTER
    FASTQ_BWA_MEM_SAMBLASTER(
        ch_trim_reads,
        ref.map { meta2, fa -> [ meta2, fa, [] ] }
    )

    ch_bam                          = FASTQ_BWA_MEM_SAMBLASTER.out.bam
    ch_versions                     = ch_versions.mix(FASTQ_BWA_MEM_SAMBLASTER.out.versions)

    // MODULE: HICQC
    ch_bam_and_ref                  = ch_bam
                                    | map { meta, bam -> [ meta.ref_id, meta, bam ] }
                                    | join(
                                        ref.map { meta2, fa -> [ meta2.id, fa ] }
                                    )
                                    | map { ref_id, meta, bam, fa ->
                                        [ [ id: "${meta.id}.on.${meta.ref_id}" ], bam, fa ]
                                    }

    HICQC ( ch_bam_and_ref.map { meta3, bam, fa -> [ meta3, bam ] } )

    ch_versions                     = ch_versions.mix(HICQC.out.versions)

    // MODULE: MAKEAGPFROMFASTA | AGP2ASSEMBLY | ASSEMBLY2BEDPE
    MAKEAGPFROMFASTA ( ch_bam_and_ref.map { meta3, bam, fa -> [ meta3.id, fa ] } )
    AGP2ASSEMBLY ( MAKEAGPFROMFASTA.out.agp )
    ASSEMBLY2BEDPE ( AGP2ASSEMBLY.out.assembly )

    ch_versions                     = ch_versions.mix(MAKEAGPFROMFASTA.out.versions.first())
                                    | mix(AGP2ASSEMBLY.out.versions.first())
                                    | mix(ASSEMBLY2BEDPE.out.versions.first())

    // MODULE: MATLOCK_BAM2_JUICER | JUICER_SORT
    MATLOCK_BAM2_JUICER ( ch_bam_and_ref.map { meta3, bam, fa -> [ meta3.id, bam ] } )

    JUICER_SORT ( MATLOCK_BAM2_JUICER.out.links )

    ch_versions                     = ch_versions.mix(MATLOCK_BAM2_JUICER.out.versions.first())
                                    | mix(JUICER_SORT.out.versions.first())

    // MODULE: RUNASSEMBLYVISUALIZER
    RUNASSEMBLYVISUALIZER ( AGP2ASSEMBLY.out.assembly.join(JUICER_SORT.out.links) )

    ch_hic                          = RUNASSEMBLYVISUALIZER.out.hic
    ch_versions                     = ch_versions.mix(RUNASSEMBLYVISUALIZER.out.versions.first())

    // MODULE: HIC2HTML
    HIC2HTML ( ch_hic )

    ch_versions                     = ch_versions.mix(HIC2HTML.out.versions.first())

    emit:
    hic                             = ch_hic
    html                            = HIC2HTML.out.html
    versions                        = ch_versions
}

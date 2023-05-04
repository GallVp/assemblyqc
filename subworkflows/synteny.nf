nextflow.enable.dsl=2

workflow SYNTENY {
    take:
        tuple_of_tag_fasta_seq_list
        tuple_of_tag_xref_fasta_seq_list
    
    main:
        if(!params.synteny.skip) {
        
            if(params.synteny.between_target_asm) {
                tuple_of_tag_fasta_seq_list
                | map {
                    [it]
                }
                | collect
                | map {
                    getUniqueWithinCombinations(it)
                }
                | flatten
                | buffer(size:6)
                | set { ch_between_target_asm_combinations }
            } else {
                ch_between_target_asm_combinations = Channel.empty()
            }
            
            ch_between_target_asm_combinations
            .mix(
                tuple_of_tag_fasta_seq_list
                | combine(
                    tuple_of_tag_xref_fasta_seq_list
                )
            )
            .map { validateSeqLists(it) }
            .tap { ch_full_tap_from_all_combinations }
            .map {
                ["${it[0]}.on.${it[3]}", it[2], it[5]] // [target.on.reference, target_seq_list, ref_seq_list]    
            }
            .set { ch_seq_lists }
            
            
            ch_full_tap_from_all_combinations
            | FILTER_SORT_FASTA
            | MUMMER
            | DNADIFF
            | CIRCOS_BUNDLE_LINKS
            | ADD_COLOUR_TO_BUNDLE_LINKS
            | join(ch_seq_lists)
            | RELABEL_BUNDLE_LINKS
            | SPLIT_BUNDLE_FILE_BY_TARGET_SEQS
            | map {
                flattenSplitBundles(it)
            }
            | flatten
            | buffer(size:3)
            | set { ch_circos_split_bundle_links }

            GET_FASTA_LEN(
                FILTER_SORT_FASTA.out.tags_fasta_files
            )
            | join(ch_seq_lists)
            | RELABEL_FASTA_LEN
            | cross(
                ch_circos_split_bundle_links
            )
            | map {
                [it[0][0], it[1][1], it[1][2], it[0][1], it[0][2]] // [target.on.reference, seq_tag, split_bundle_file, target_seq_len, ref_seq_len]
            }
            | GENERATE_KARYOTYPE
            | join(
                ch_circos_split_bundle_links
                | map {
                    ["${it[0]}.${it[1]}", it[2]] // [target.on.reference.seq_tag, split_bundle_file]
                }
            )
            | map {
                failIfNumberOfLinksTooLarge(it, 20000)
            }
            | CIRCOS

            CIRCOS
            .out
            .png_file
            .collect()
            .set{ ch_list_of_circos_plots }
        }
        else {
            ch_list_of_circos_plots = Channel.of([])
        }
    
    emit:
        list_of_circos_plots = ch_list_of_circos_plots
}

def getUniqueWithinCombinations(inputArray) {
    if (inputArray.size() <= 1) {
        return []
    }

    def outputList = []

    for (int i = 0; i < inputArray.size() - 1; i++) {
        for (int j = i + 1; j < inputArray.size(); j++) {
            def combination = [
                inputArray[i][0],
                file(inputArray[i][1], checkIfExists: true),
                file(inputArray[i][2], checkIfExists: true),
                inputArray[j][0],
                file(inputArray[j][1], checkIfExists: true),
                file(inputArray[j][2], checkIfExists: true)
            ]
            outputList.add(combination)
        }
    }
    return outputList
}

def validateSeqLists(inputArray) {

    file1 = inputArray[2]
    file2 = inputArray[5]

    def lines1 = file(file1).readLines()
    def lines2 = file(file2).readLines()

    lines1.each { line ->
        def columns = line.split()
        if (columns.size() != 2) {
            throw new Exception("Error: Sequence file ${file1.getName()} does not have exactly two columns.")
        }
    }

    lines2.each { line ->
        def columns = line.split()
        if (columns.size() != 2) {
            throw new Exception("Error: Sequence file ${file2.getName()} does not have exactly two columns.")
        }
    }
    
    def outputLines = lines1 + lines2
    
    def secondColumn = outputLines.collect { it.split()[1] }
    if (secondColumn.size() != secondColumn.unique().size()) {
        throw new Exception("Error: Duplicate sequence labels detected in second column for pair: ${file1.getName()}, ${file2.getName()}")
    }
    
    return inputArray
}

def appendTags(tag, valuesArray) {
    if (valuesArray.size() <= 1) {
        return []
    }

    def outputList = []

    for (int i = 0; i < valuesArray.size(); i++) {
        outputList.add([tag, valuesArray[i]])
    }
    return outputList
}

def flattenSplitBundles(inputArray) {
    def target_on_ref = inputArray[0]
    def files = inputArray[1]

    if(files in ArrayList) {
        return files.collect { [target_on_ref, extractBundleTag(it), it] }
    } else {
        return [files].collect { [target_on_ref, extractBundleTag(it), it] }
    }
}

def extractBundleTag(filePath) {
   def regex = /.*\.(\w+)\.split\.bundle\.txt/
   def matcher = filePath =~ regex
   if (matcher.matches()) {
      return matcher.group(1)
   } else {
      throw new Exception("Error: Failed to parse the sequence tag from file name: ${filePath.getName()}")
   }
}

def failIfNumberOfLinksTooLarge(inputTuple, maxLinks) {

    filePath = inputTuple[2]

    def lineCount = 0
    file(filePath).eachLine {
        lineCount++
        if (lineCount > maxLinks) {
            throw new RuntimeException("Link count exceeded ${maxLinks} for ${filePath}." +
            " Try to shrink the number of links by increasing the max_gap and min_bundle_size options in the config file.")
        }
    }

    return inputTuple
}

process FILTER_SORT_FASTA {
    tag "${target}:${reference}"
    container "quay.io/biocontainers/samtools:1.16.1--h6899075_1"

    input:
        tuple val(target), path(target_fasta), path(target_seq_list), val(reference), path(ref_fasta), path(ref_seq_list)
    
    output:        
        tuple val(target), val(reference), path("filtered.ordered.target.fasta"), path("filtered.ordered.ref.fasta"), emit: tags_fasta_files
    
    script:
        """
        samtools faidx $target_fasta \$(awk '{print \$1}' $target_seq_list) > filtered.ordered.target.fasta
        samtools faidx $ref_fasta \$(awk '{print \$1}' $ref_seq_list) > filtered.ordered.ref.fasta
        """
}

process GET_FASTA_LEN {
    tag "${target}.on.${reference}"
    container "quay.io/biocontainers/samtools:1.16.1--h6899075_1"
    
    input:        
        tuple val(target), val(reference), path(filtered_ordered_target_fasta), path(filtered_ordered_ref_fasta)
    
    output:
        tuple val("${target}.on.${reference}"), path("target.seq.lengths"), path("ref.seq.lengths"), emit: tags_len_files
    
    script:
        """
        samtools faidx $filtered_ordered_target_fasta
        samtools faidx $filtered_ordered_ref_fasta

        cat "${filtered_ordered_target_fasta}.fai" | awk '{print \$1, \$2}' OFS="\\t" > target.seq.lengths
        cat "${filtered_ordered_ref_fasta}.fai" | awk '{print \$1, \$2}' OFS="\\t" > ref.seq.lengths
        """
}

process MUMMER {
    tag "${target}.on.${reference}"
    label 'uses_high_cpu_mem'
    label 'uses_64_gb_mem'
    label 'takes_four_hours'
    container "docker://staphb/mummer:4.0.0"

    input:
        tuple val(target), val(reference), path(target_fasta), path(ref_fasta)
    
    output:
        tuple val("${target}.on.${reference}"), path("*.delta")
    
    script:
        """
        nucmer \
        --mum \
        -t ${task.cpus * params.ht_factor} \
        -p "${target}.on.${reference}" \
        $ref_fasta \
        $target_fasta
        """
}

process DNADIFF {
    tag "${target_on_ref}"
    label 'takes_two_hours'
    container "docker://staphb/mummer:4.0.0"

    input:
        tuple val(target_on_ref), path(dnadiff_file)
    
    output:
        tuple val(target_on_ref), path("*.xcoords"), path("*.report")
    
    script:
        """
        dnadiff \
        -p $target_on_ref \
        -d $dnadiff_file

        if [[ "${params.synteny.many_to_many_align}" = "1" ]];then
            cat "${target_on_ref}.mcoords" > "${target_on_ref}.m.xcoords"
        else
            cat "${target_on_ref}.1coords" > "${target_on_ref}.1.xcoords"
        fi
        """
}

process CIRCOS_BUNDLE_LINKS {
    tag "${target_on_ref}"
    label 'takes_two_hours'
    container "docker://gallvp/circos-tools:0.23-1"

    input:
        tuple val(target_on_ref), path(coords_file), path(report_file)
    
    output:
        tuple val(target_on_ref), path("*.xcoords.bundle.txt")
    
    script:
        """
        cat $coords_file | awk '{print \$12,\$1,\$2,\$13,\$3,\$4}' OFS="\\t" > "\$(basename $coords_file).links.txt"

        /usr/share/circos/tools/bundlelinks/bin/bundlelinks \
        -links "\$(basename $coords_file).links.txt" \
        -max_gap "${params.synteny.max_gap}" \
        -min_bundle_size "${params.synteny.min_bundle_size}" \
        1>"\$(basename $coords_file).bundle.txt" \
        2>bundlelinks.err
        """
}

process ADD_COLOUR_TO_BUNDLE_LINKS {
    tag "${target_on_ref}"

    input:
        tuple val(target_on_ref), path(bundle_links)
    
    output:
        tuple val(target_on_ref), path("*.xcoords.bundle.coloured.txt"), emit: coloured_bundle_links
    
    script:
        """
        add_color_2_circos_bundle_file.pl \
        -i="${bundle_links}" \
        -o="\$(basename $bundle_links .bundle.txt).bundle.coloured.txt"
        """
}

process RELABEL_BUNDLE_LINKS {
    tag "${target_on_ref}"
    conda 'environment.yml'
    
    input:
        tuple val(target_on_ref), path(coloured_bundle_links), path(target_seq_list), path(ref_seq_list)
    
    output:
        tuple val(target_on_ref), path("*.xcoords.bundle.coloured.relabeled.txt"), emit: relabeled_coloured_bundle_links
    
    script:
        """
        #!/usr/bin/env python

        import pandas as pd
        import sys
        import os

        output_file_name = ".".join("$coloured_bundle_links".split(".")[0:-1]) + ".relabeled.txt"

        subs_target_seq = pd.read_csv('$target_seq_list', sep='\\t', header=None)
        subs_target_seq_dict = dict(zip(subs_target_seq.iloc[:, 0], subs_target_seq.iloc[:, 1]))

        subs_ref_seq = pd.read_csv('$ref_seq_list', sep='\\t', header=None)
        subs_ref_seq_dict = dict(zip(subs_ref_seq.iloc[:, 0], subs_ref_seq.iloc[:, 1]))
        
        if os.path.getsize('$coloured_bundle_links') == 0:
            with open(output_file_name, 'w') as f:
                f.write('')
            sys.exit(0)
        else:
            df = pd.read_csv('$coloured_bundle_links', sep=' ', header=None)
        
        df.iloc[:, 3] = df.iloc[:, 3].replace(subs_target_seq_dict, regex=False)
        df.iloc[:, 0] = df.iloc[:, 0].replace(subs_ref_seq_dict, regex=False)
        
        df.to_csv(output_file_name, sep=' ', index=False, header=None)
        """
}

process RELABEL_FASTA_LEN {
    tag "${target_on_ref}"
    conda 'environment.yml'
    
    input:
        tuple val(target_on_ref), path(target_seq_lengths), path(ref_seq_lengths), path(target_seq_list), path(ref_seq_list)
    
    output:
        tuple val(target_on_ref), path("relabeld.target.seq.lengths"), path("relabeld.ref.seq.lengths"), emit: relabeled_seq_lengths
    
    script:
        """
        #!/usr/bin/env python

        import pandas as pd

        subs_target_seq = pd.read_csv('$target_seq_list', sep='\\t', header=None)
        subs_target_seq_dict = dict(zip(subs_target_seq.iloc[:, 0], subs_target_seq.iloc[:, 1]))

        subs_ref_seq = pd.read_csv('$ref_seq_list', sep='\\t', header=None)
        subs_ref_seq_dict = dict(zip(subs_ref_seq.iloc[:, 0], subs_ref_seq.iloc[:, 1]))
        
        df_target_seq_lengths = pd.read_csv('$target_seq_lengths', sep='\\t', header=None)
        df_target_seq_lengths.iloc[:, 0] = df_target_seq_lengths.iloc[:, 0].replace(subs_target_seq_dict, regex=False)
        df_target_seq_lengths.to_csv("relabeld.target.seq.lengths", sep='\\t', index=False, header=None)

        df_ref_seq_lengths = pd.read_csv('$ref_seq_lengths', sep='\\t', header=None)
        df_ref_seq_lengths.iloc[:, 0] = df_ref_seq_lengths.iloc[:, 0].replace(subs_ref_seq_dict, regex=False)
        df_ref_seq_lengths.to_csv("relabeld.ref.seq.lengths", sep='\\t', index=False, header=None)
        """
}

process SPLIT_BUNDLE_FILE_BY_TARGET_SEQS {
    tag "${target_on_ref}"

    input:
        tuple val(target_on_ref), path(coloured_bundle_links)
    
    output:
        tuple val(target_on_ref), path("*.split.bundle.txt")
    
    script:
        """
        if [[ "${params.synteny.plot_1_vs_all}" = "1" ]];then
            target_seqs=(\$(awk '{print \$4}' $coloured_bundle_links | sort | uniq))
            
            for i in "\${!target_seqs[@]}"
            do
                target_seq=\${target_seqs[\$i]}
                awk -v seq="\$target_seq" '\$4==seq {print \$0}' $coloured_bundle_links > "${target_on_ref}.\${target_seq}.split.bundle.txt"
            done
        fi

        cat $coloured_bundle_links > "${target_on_ref}.all.split.bundle.txt"
        """
}

process GENERATE_KARYOTYPE {
    tag "${target_on_ref}.${seq_tag}"

    input:
        tuple val(target_on_ref), val(seq_tag), path(split_bundle_file), path(target_seq_len), path(ref_seq_len)
    
    output:
        tuple val("${target_on_ref}.${seq_tag}"), path("*.karyotype")
    
    script:
        """
        ref_seqs=(\$(awk '{print \$1}' $split_bundle_file | sort | uniq))

        if [ \${#ref_seqs[@]} -eq 0 ]; then
            touch "${target_on_ref}.${seq_tag}.karyotype"
            exit 0
        fi

        tmp_file=\$(mktemp)
        printf '%s\\n' "\${ref_seqs[@]}" > "\$tmp_file"

        if [[ $seq_tag = "all" ]];then
            cat $target_seq_len > filtered.target.seq.len
        else
            grep -w "$seq_tag" $target_seq_len > filtered.target.seq.len
        fi
        cat filtered.target.seq.len | awk '{print \$1,\$2,"red"}' OFS="\\t" > colored.filtered.target.seq.len

        grep -w -f "\$tmp_file" $ref_seq_len > filtered.ref.seq.len
        cat filtered.ref.seq.len | awk '{print \$1,\$2,"blue"}' OFS="\\t" > colored.filtered.ref.seq.len

        cat colored.filtered.ref.seq.len | sort -k1V > merged.seq.lengths
        cat colored.filtered.target.seq.len | sort -k1Vr >> merged.seq.lengths
        sed -i '/^\$/d' merged.seq.lengths
        
        cat merged.seq.lengths \
        | awk '{print "chr -",\$1,\$1,"0",\$2-1,\$3}' OFS="\\t" \
        > "${target_on_ref}.${seq_tag}.karyotype"

        rm "\$tmp_file"
        """
}

process CIRCOS {
    tag "${target_on_ref_seq}"
    container "docker://gallvp/circos-tools:0.23-1" 
    publishDir "${params.outdir.main}/synteny/${target_on_ref_seq}", mode: 'copy'

    input:
        tuple val(target_on_ref_seq), path(karyotype), path(bundle_file)
    
    output:
        path "*.svg", emit: svg_file
        path "*.png", emit: png_file
        path "bundled.links.tsv", emit: bundled_links_tsv
        path "circos.conf", emit: circos_conf
        path "karyotype.tsv", emit: karyotype_tsv
    
    script:
        """

        cat $karyotype > "karyotype.tsv"
        cat $bundle_file | awk '{print \$1,\$2,\$3,\$4,\$5,\$6,\$7}' OFS="\\t" > bundled.links.tsv

        num_sequences=\$(cat $karyotype | wc -l)
        if (( \$num_sequences <= 10 )); then
            label_font_size=40
        elif (( \$num_sequences <= 30 )); then
            label_font_size=30
        else
            label_font_size=15
        fi

        if (( \$num_sequences <= 10 )); then
            ticks_config="<ticks>
            radius                      = dims(ideogram,radius_outer)
            orientation                 = out
            label_multiplier            = 1e-6
            color                       = black
            thickness                   = 5p
            label_offset                = 5p
            <tick>
                spacing                 = 0.5u
                size                    = 10p
                show_label              = yes
                label_size              = 20p
                format                  = %.1f
            </tick>
            <tick>
                spacing                 = 1.0u
                size                    = 15p
                show_label              = yes
                label_size              = 30p
                format                  = %.1f
            </tick>
            </ticks>"
            
            label_offset=" + 120p"
        else
            ticks_config=""
            
            label_offset=" + 25p"
        fi

        cat <<- EOF > circos.conf
        # circos.conf
        karyotype = $karyotype

        <ideogram>
            <spacing>
                default             = 0.005r
            </spacing>

            radius                  = 0.8r
            thickness               = 25p
            fill                    = yes
            stroke_thickness        = 0

            show_label              = yes
            label_font              = default
            label_radius            = dims(ideogram,radius_outer)\$label_offset
            label_size              = \$label_font_size
            label_parallel          = yes
        </ideogram>

        <links>
            radius                  = 0.99r
            crest                   = 1
            ribbon                  = yes
            flat                    = yes
            stroke_thickness        = 0
            color                   = grey_a3

            bezier_radius           = 0r
            bezier_radius_purity    = 0.5
            <link>
                file                = bundled.links.tsv
            </link>
        </links>

        show_ticks                  = yes
        show_tick_labels            = yes
        chromosomes_units           = 1000000
        chromosomes_display_default = yes
        
        \$ticks_config
        
        <image>
            <<include /usr/share/circos/etc/image.conf>>
        </image>
        <<include /usr/share/circos/etc/colors_fonts_patterns.conf>>
        <<include /usr/share/circos/etc/housekeeping.conf>>
EOF

        if [ ! -s $karyotype ]; then
            touch "${target_on_ref_seq}.svg"
            touch "${target_on_ref_seq}.png"
            exit 0
        fi

        circos

        mv circos.svg "${target_on_ref_seq}.svg"
        mv circos.png "${target_on_ref_seq}.png"
        """
}
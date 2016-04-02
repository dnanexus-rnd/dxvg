#!/bin/bash

main() {
    set -ex -o pipefail

    # launch subjob to construct graph for each contig
    jbors=""
    for reference_contig in "${reference_contigs[@]}"; do
        process_job=$(dx-jobutil-new-job process --name "construct $reference_contig" \
                                                 -i "construct_options=${construct_options}" \
                                                 -i "reference_contig=${reference_contig}" \
                                                 -i "reference_genome=${reference_genome}" \
                                                 -i "reference_variants=${reference_variants}")
        jbors="$jbors -i vg:array:jobref=${process_job}:vg"
    done

    # schedule postprocessing job
    if [ -z "$output_name" ]; then
        output_name="$reference_genome_prefix"
    fi
    postprocess_job=$(dx-jobutil-new-job postprocess -i "output_name=${output_name}" $jbors)
    dx-jobutil-add-output vg_tar "${postprocess_job}:vg_tar" --class=jobref
}

process() {
    set -ex -o pipefail

    # fetch reference data
    dx cat "$reference_genome" | zcat > reference_genome.fa &
    dx download "$reference_variants" -o variants.vcf.gz
    tabix variants.vcf.gz
    wait

    # construct graph
    vg construct -R "$reference_contig" -r reference_genome.fa -v variants.vcf.gz -t $(nproc) $construct_options > "${reference_contig}.vg"

    # output to temp space
    dx-jobutil-add-output vg --class=file \
        $(dx upload --brief "${reference_contig}.vg")
}

postprocess() {
    set -ex -o pipefail

    mkdir vg
    pushd vg
    # stage graphs from temp space
    for vg_i in "${vg[@]}"; do
        dx download "$vg_i"
    done
    # rewrite IDs
    vg ids -j $(ls -1 *.vg)
    popd

    # tar up and output
    vg_tar=$(tar cv vg | dx upload --destination "${output_name}.vg.tar" --type vg_tar --brief -)
    dx-jobutil-add-output vg_tar "$vg_tar" --class=file
}

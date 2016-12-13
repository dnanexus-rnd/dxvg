#!/bin/bash

main() {
    set -ex -o pipefail

    # fetch reference data
    dx cat "$reference_genome" | zcat > reference_genome.fa &
    dx download "$reference_variants" -o variants.vcf.gz
    tabix variants.vcf.gz
    wait

    # construct graphs
    mkdir vg
    pushd vg
    export -f construct_contig
    export SHELL=/bin/bash
    printf '%s\n' ${reference_contigs[@]} | parallel -j `nproc` construct_contig {}
    ls -lh *.vg

    # rewrite IDs
    vg ids -j $(ls -1 *.vg)

    # tar up and output
    popd
    if [ -z "$output_name" ]; then
        output_name="$reference_genome_prefix"
    fi
    vg_tar=$(tar cv vg | dx upload --destination "${output_name}.vg.tar" --type vg_tar --brief -)
    dx-jobutil-add-output vg_tar "$vg_tar" --class=file
}

construct_contig() {
    set -ex -o pipefail
    vg construct -r ../reference_genome.fa -v ../variants.vcf.gz \
        --region "$1" --region-is-chrom \
        -t 1 $construct_options > "$1.vg"
}

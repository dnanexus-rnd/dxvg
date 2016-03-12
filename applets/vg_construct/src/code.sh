#!/bin/bash

main() {
    set -ex -o pipefail

    # fetch reference data
    dx cat "$reference_genome" | zcat > reference_genome.fa &
    dx download "$reference_variants" -o variants.vcf.gz
    tabix variants.vcf.gz
    wait

    # construct graph
    mkdir vg
    printf '%s\n' "${reference_contigs[@]}" | \
        xargs -i bash -ex -c "vg construct -R {} -r reference_genome.fa -v variants.vcf.gz -t $(nproc) $construct_options > vg/{}.vg"

    # rewrite IDs
    vg ids -j $(printf 'vg/%s.vg\n' "${reference_contigs[@]}")

    # tar everything up and output
    if [ -z "$output_name" ]; then
        output_name="$reference_genome_prefix"
    fi
    vg_tar=$(tar cv vg | dx upload --destination "${output_name}.vg.tar" --type vg_tar --brief -)
    dx-jobutil-add-output vg_tar "$vg_tar" --class=file
}

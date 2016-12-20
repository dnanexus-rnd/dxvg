#!/bin/bash

main() {
    set -ex -o pipefail
    export SHELL=/bin/bash

    # fetch reference data
    stage_reference_genome "$reference_genome" & srgpid=$!
    variants_arg=""
    if [ -n "$reference_variants" ]; then
        dx download "$reference_variants" -o variants.vcf.gz
        tabix variants.vcf.gz
        variants_arg='-v variants.vcf.gz'
    else
        echo "Constructing graph from reference genome only!!!"
    fi
    wait $srgpid

    # construct graphs
    mkdir vg
    printf '%s\n' ${reference_contigs[@]} | parallel -t -j `nproc` \
        vg construct -r reference_genome.fa $variants_arg --region '{}' --region-is-chrom -t 1 $construct_options '>' 'vg/{}.vg'
    ls -lh vg/

    # rewrite IDs
    vg ids -j $(ls -1 vg/*.vg | sort -V)

    # tar up and output
    if [ -z "$output_name" ]; then
        output_name="$reference_genome_prefix"
    fi
    vg_tar=$(tar cv vg | dx upload --destination "${output_name}.vg.tar" --type vg_tar --brief -)
    dx-jobutil-add-output vg_tar "$vg_tar" --class=file

    # create ref-only versions
    mv vg/ var_vg/
    mkdir vg
    printf '%s\n' ${reference_contigs[@]} | parallel -t -j 4 vg mod -N 'var_vg/{}.vg' '>' 'vg/{}.ref.vg'

    ref_vg_tar=$(tar cv vg | dx upload --destination "${output_name}.ref.vg.tar" --type vg_tar --brief -)
    dx-jobutil-add-output ref_vg_tar "$ref_vg_tar" --class=file
}

stage_reference_genome() {
    set -ex -o pipefail
    # ignore nonzero exit status due to maddening "trailing garbage" in hs37d5.fa.gz
    (dx cat "$1" | zcat > reference_genome.fa) || true
    samtools faidx reference_genome.fa
}

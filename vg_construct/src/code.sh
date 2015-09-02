#!/bin/bash

main() {
    set -ex -o pipefail

    # install dependencies
    sudo rm -f /etc/apt/apt.conf.d/99dnanexus
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    sudo apt-get -qq update
    sudo apt-get -qq install -y gcc-4.9 g++-4.9 

    # install vg executable
    dx cat "$vg_exe" | zcat > /usr/local/bin/vg
    chmod +x /usr/local/bin/vg

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

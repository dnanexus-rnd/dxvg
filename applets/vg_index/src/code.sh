#!/bin/bash

main() {
    set -ex -o pipefail

    # unpack vg tar
    dx cat "$vg_tar" | tar vx
    pushd vg

    # build xg index
    vg index -x index.xg $(ls -1 *.vg)

    # build GCSA index
    mkdir -p /tmp/dxvg
    kmers=""
    for vgfn in $(ls -1 *.vg); do
        seqname=${vgfn%.vg}
        kmers="$kmers -i /tmp/dxvg/${seqname}.kmers"
        vg mod -p -t $(nproc) $prune_complex_options "$vgfn" | \
            vg mod -S $prune_subgraphs_options - | \
            vg kmers -gB -t $(nproc) -H 1000000000 -T 1000000001 $kmers_options - > "/tmp/dxvg/${seqname}.kmers"
    done
    ls -1sh /tmp/dxvg
    vg index -g index.gcsa $gcsa_options $kmers

    # tar everything up and output
    popd
    index_options_alnum=$(echo "${prune_complex_options}${prune_subgraphs_options}${kmers_options}${gcsa_options}" | tr -cd '[[:alnum:]]')
    vg_indexed_tar=$(tar cv vg | \
                       dx upload --destination "${vg_tar_prefix}.vg.index_${index_options_alnum}.tar" \
                         --property "prune_complex_options=${prune_complex_options}" \
                         --property "prune_subgraphs_options=${prune_subgraphs_options}" \
                         --property "kmers_options=${kmers_options}" \
                         --property "gcsa_options=${gcsa_options}" \
                         --type vg_indexed_tar --brief -)
    dx-jobutil-add-output vg_indexed_tar "$vg_indexed_tar" --class=file
}

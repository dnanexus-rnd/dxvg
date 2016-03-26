#!/bin/bash

main() {
    set -ex -o pipefail

    # install dependencies
    sudo dpkg -i /tmp/dx_deb_bundle/*.deb

    # unpack vg tar
    dx cat "$vg_tar" | tar vx
    pushd vg

    # build xg index
    vg index $index_options -x index.xg $(ls -1 *.vg)

    # build GCSA index
    mkdir -p /tmp/dxvg
    graphs=""
    for vgfn in $(ls -1 *.vg); do
        seqname=${vgfn%.vg}
        graphs="$graphs /tmp/dxvg/${seqname}"
        vg mod -p -t $(nproc) $prune_complex_options "$vgfn" | \
            vg mod -S $prune_subgraphs_options - > "/tmp/dxvg/${seqname}.mod.vg"
        vg kmers -gB -t $(nproc) -H 1000000000 -T 1000000001 $kmers_options "/tmp/dxvg/${seqname}.mod.vg" > "/tmp/dxvg/${seqname}.graph"
    done
    ls -1sh /tmp/dxvg
    build_gcsa -d 1 -o index $graphs
    mv index.lcp index.gcsa.lcp

    # tar everything up and output
    popd
    index_options_alnum=$(echo "${prune_complex_options}${prune_subgraphs_options}${kmers_options}" | tr -cd '[[:alnum:]]')
    vg_indexed_tar=$(tar cv vg | \
                       dx upload --destination "${vg_tar_prefix}.vg.index_${index_options_alnum}.tar" \
                         --property "prune_complex_options=${prune_complex_options}" \
                         --property "prune_subgraphs_options=${prune_subgraphs_options}" \
                         --property "kmers_options=${kmers_options}" \
                         --type vg_indexed_tar --brief -)
    dx-jobutil-add-output vg_indexed_tar "$vg_indexed_tar" --class=file
}

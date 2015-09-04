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

    # unpack vg tar
    dx cat "$vg_tar" | tar vx

    # build index
    vg index $index_options -s -d vg/index -t $(nproc) $(ls -1 vg/*.vg)

    # tar everything up and output
    index_options_alnum=$(echo "$index_options" | tr -cd '[[:alnum:]]')
    vg_indexed_tar=$(tar cv vg | \
                       dx upload --destination "${vg_tar_prefix}.vg.index_${index_options_alnum}.tar" \
                         --type vg_indexed_tar --property "index_options=${index_options}" --brief -)
    dx-jobutil-add-output vg_indexed_tar "$vg_indexed_tar" --class=file
}

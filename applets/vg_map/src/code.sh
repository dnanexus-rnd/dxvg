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

    # download stuff
    pids=()
    dx cat "$vg_indexed_tar" | tar vx & pids+=($!)
    dx download "$reads" -o reads.fastq.gz & pids+=($!)
    if [ -n "$reads2" ]; then
        dx download "$reads2" -o reads2.fastq.gz
    fi
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # build index
    r2cmd=""
    if [ -n "$reads2" ]; then
        r2cmd="-f reads2.fastq.gz"
    fi
    gam=$(vg map -f reads.fastq.gz $r2cmd -d vg/index -t $(nproc) $map_options \
            | dx upload --destination "${reads_prefix}.gam" --brief -)
    dx-jobutil-add-output gam "$gam" --class=file
}

#!/bin/bash

main() {
    set -ex -o pipefail

    # install dependencies
    sudo dpkg -i /tmp/dx_deb_bundle/*.deb

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

#!/bin/bash

main() {
    set -ex -o pipefail

    # download stuff
    dx cat "$vg_indexed_tar" | tar vx
    dx-download-all-inputs --except vg_indexed_tar --parallel

    # run vg filter    
    mkdir -p out/gams
    if [ -z "$output_prefix" ]; then
        output_prefix="${gam_prefix}"
    fi
    vg filter -x vg/index.xg -B "out/gams/${output_prefix}" -R in/ranges/* in/gam/*
    find out -type f

    dx-upload-all-outputs --parallel
}

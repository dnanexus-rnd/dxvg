#!/bin/bash

main() {
    set -ex -o pipefail

    # download stuff
    dx cat "$vg_indexed_tar" | tar vx
    dx-download-all-inputs --except vg_indexed_tar --parallel

    # run vg filter    
    mkdir -p out/gams
    vg filter -x vg/index.xg -B "out/gams/${gam_prefix}-chunk" -R in/ranges/* in/gam/*
    find out -type f

    dx-upload-all-outputs --parallel
}

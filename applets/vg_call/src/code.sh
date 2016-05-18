#!/bin/bash

main() {
    set -ex -o pipefail

    dpkg -i /tmp/dx_deb_bundle/*.deb

    # download stuff
    dx cat "$vg_indexed_tar" | tar vx
    dx-download-all-inputs --except vg_indexed_tar --parallel
    dx download "$glenn2vcf" -o /usr/local/bin/glenn2vcf
    chmod +x /usr/local/bin/glenn2vcf

    # run chunked_call
    exit_code=0
    python /usr/local/bin/chunked_call vg/index.xg in/gam/* \
            "$chromosome" "$chromosome_length" "$sample_name" results \
            --call_opts "$call_opts" --chunk 25000000 --threads $(nproc) \
            || exit_code=$?
    find results -type f
    if [ "$exit_code" -ne "0" ]; then
        cd results
        cat $(ls -t1 *.log | head -n 1)
        exit $exit_code
    fi

    # upload outputs
    mkdir -p out/vcf/
    cp "results/${chromosome}.vcf.gz" out/vcf/
    find out -type f

    dx-upload-all-outputs --parallel
}

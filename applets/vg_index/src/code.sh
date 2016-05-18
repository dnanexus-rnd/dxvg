#!/bin/bash

main() {
    set -ex -o pipefail

    # launch xg build
    xgjob=$(dx-jobutil-new-job xg -i "vg_tar=${vg_tar}")

    # unpack vg tar
    dx cat "$vg_tar" | tar vx
    pushd vg

    # launch kmers jobs
    mkdir -p /tmp/dxvg
    jbors=""
    for vgfn in $(ls -1 *.vg); do
        vg_i=$(dx upload --brief "$vgfn")
        kmers_job=$(dx-jobutil-new-job kmers --name "$vgfn kmers" -i "vg=${vg_i}" \
                                             -i "kmers_options=${kmers_options}")
        jbors="$jbors -i kmers:array:jobref=${kmers_job}:kmers"
    done

    # schedule gcsa job
    gcsajob=$(dx-jobutil-new-job gcsa -i "vg_tar=${vg_tar}" -i "vg_tar_prefix=${vg_tar_prefix}" \
                                      -i xgjob:string=${xgjob} \
                                      -i "kmers_options=${kmers_options}" -i "gcsa_options=${gcsa_options}" \
                                      $jbors)
    dx-jobutil-add-output vg_indexed_tar --class=jobref "$gcsajob:vg_indexed_tar" 
}

xg() {
    set -ex -o pipefail

    # unpack vg tar
    dx cat "$vg_tar" | tar vx
    pushd vg

    # build xg index
    vg index -x index.xg $(ls -1 *.vg)

    # upload it to temp storage
    dx-jobutil-add-output xg --class=file $(dx upload --brief index.xg)
}

kmers() {
    set -ex -o pipefail

    vg_name=$(dx describe --name "$vg")
    vg_name=${vg_name%.vg}

    dx-jobutil-add-output kmers --class=file \
        $(dx cat "$vg" \
            | vg mod -N -t $(nproc) -r "$vg_name" - \
            | vg kmers -gB -t $(nproc) -H 1000000000 -T 1000000001 $kmers_options - \
            | dx upload --destination "${vg_name}.kmers" --brief -)
}

gcsa() {
    set -ex -o pipefail

    mkdir vg

    # spawn background downloads of vg tar and xg index.
    dx cat "$vg_tar" | tar vx & vgpid=$!
    download_xg "$xgjob" & xgpid=$!

    # download kmers
    mkdir -p /tmp/kmers
    cd /tmp/kmers
    for kmers_i in "${kmers[@]}"; do
        dx download "$kmers_i"
    done
    ls -1sh /tmp/kmers/*.kmers

    # build GCSA index
    cd /home/dnanexus
    vg index -g vg/index.gcsa $gcsa_options $(printf " -i %s" $(find /tmp/kmers -name "*.kmers" -type f))

    # tar everything up and output
    wait $vgpid
    wait $xgpid
    index_options_alnum=$(echo "${kmers_options}${gcsa_options}" | tr -cd '[[:alnum:]]')
    vg_indexed_tar=$(tar cv vg | \
                       dx upload --destination "${vg_tar_prefix}.vg.index_${index_options_alnum}.tar" \
                         --property "kmers_options=${kmers_options}" \
                         --property "gcsa_options=${gcsa_options}" \
                         --type vg_indexed_tar --brief -)
    dx-jobutil-add-output vg_indexed_tar "$vg_indexed_tar" --class=file
}

download_xg() {
    set -ex -o pipefail

    # download the xg index in the background of the GCSA-building job. This
    # is a bit convoluted because we're trying to save overhead by not having
    # either job formally depend on the other. We assume the GCSA index takes
    # much longer to build than the xg index.

    dx wait "$1"
    xgdxfile=$(dx describe "$1" --json | jq '.output.xg')
    xgdxfile=$(dx-jobutil-parse-link --no-project "$xgdxfile")
    dx wait "$xgdxfile"
    dx download "$xgdxfile" -o /home/dnanexus/vg/index.xg
}

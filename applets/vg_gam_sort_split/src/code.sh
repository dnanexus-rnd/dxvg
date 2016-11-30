#!/bin/bash

main() {
    set -ex -o pipefail

    # stage graph & indices
    dx cat "$vg_indexed_tar" | tar vx

    if [ -z "$output_prefix" ]; then
        gam0=$(dx describe --name "${gam[0]}")
        output_prefix="${gam0%.gam}"
    fi

    # stream the GAM into index database
    dx cat "${gam[@]}" \
        | vg index --store-alignments -d "${output_prefix}.gam.db" -t `nproc` -
    ls -lh "${output_prefix}.gam.db"

    # background tar and upload the database
    tar c "${output_prefix}.gam.db" \
        | dx upload --destination "${output_prefix}.gam.db.tar" --brief - \
        > /tmp/GAMDBTAR_DXID & gamdbtar_pid=$!
    dxid=$(dx upload --destination "${output_prefix}.rocksdb.log" --brief "${output_prefix}.gam.db/LOG")
    dx-jobutil-add-output rocksdb_log "$dxid"

    # generate desired sorted GAMs from the database
    export -f process_range
    export -f vg_pos2id
    export SHELL=/bin/bash
    if [ "${#ranges[@]}" -gt "0" ]; then
        parallel --verbose process_range "$output_prefix" ::: "${ranges[@]}" \
            | xargs --verbose -i dx-jobutil-add-output --array sorted_gams {}
    fi

    # complete previous background upload
    wait $gamdbtar_pid
    dxid=$(cat /tmp/GAMDBTAR_DXID | tr -d '\n')
    dx-jobutil-add-output alignment_index "$dxid"
}

process_range() {
    set -ex -o pipefail
    output_prefix="$1"
    range="$2"

    # parse the range
    range_tsv=$(echo -n "$range" | tr ':-' $'\t')
    path=$(echo -n "$range_tsv" | cut -f1)
    lo=$(echo -n "$range_tsv" | cut -f2)
    hi=$(echo -n "$range_tsv" | cut -f3)

    # resolve the start and end node IDs in the graph.
    node_start=$(vg_pos2id "$path" "$lo")
    node_end=$(vg_pos2id "$path" "$hi")

    # generate gam from database; stream-upload and emit id to standard output
    vg find -d "${output_prefix}.gam.db" -i "${node_start}:${node_end}" \
        | dx upload --destination "${output_prefix}.${path}_${lo}_${hi}.${node_start}_${node_end}.gam" --brief -
}

# resolve a one-based position to a node ID
vg_pos2id() {
    path="$1"
    pos="$2"
    # vg find -p range offsets are 0-based
    pos=$(( pos - 1))
    # serialize this because `vg find` uses a lot of memory
    # for the xg index
    touch /var/lock/vg_find
    flock /var/lock/vg_find vg find -x vg/index.xg -p "${path}:${pos}-${pos}" | vg mod -o - | vg view -j - | jq .node[0].id
}

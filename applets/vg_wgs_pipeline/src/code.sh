#!/bin/bash

main() {
    set -ex -o pipefail

    # launch vg_map on each fastq pair
    fastq_pairs="${#reads[@]}"
    if [ "$fastq_pairs" -ne "${#reads2[@]}" ]; then
        dx-jobutil-report-error "fastqs input arrays have unequal lengths" AppError
        exit 1
    fi
    vg_map_jobs=()
    for i in $(seq 0 $(expr $fastq_pairs - 1)); do
        vg_map_jobs+=($(dx run $(dx-jobutil-parse-link --no-project "$vg_map") \
                               -i reads="${reads[$i]}" \
                               -i reads2="${reads2[$i]}" \
                               -i map_options="-M 2 -W 1000 -u 0 -U -n 5" \
                               -i vg_indexed_tar="$vg_indexed_tar" \
                               --name "map shard $(expr $i + 1)" \
                               -y --brief))
    done

    # schedule file concatenator to make one gam
    file_concatenator_args=$(printf " -i files=%s:gam" ${vg_map_jobs[@]})
    concat_job=$(dx run file_concatenator $file_concatenator_args -i output_filename="${output_name}.gam" \
                    --name "concatenate mappings shards" -y --brief)
    dx-jobutil-add-output gam --class=jobref ${concat_job}:file

    # schedule calling jobs on each chromosome
    vcf_in=""
    n_chromosomes="${#chromosomes[@]}"
    if [ "$n_chromosomes" -ne "${#chromosome_lengths[@]}" ]; then
        dx-jobutil-report-error "chromosomes and chromosome_lengths input arrays have unequal lengths" AppError
        exit 1
    fi
    for i in $(seq 0 $(expr $n_chromosomes - 1)); do
        vg_call_job=$(dx run $(dx-jobutil-parse-link --no-project "$vg_call") \
                             -i vg_indexed_tar="$vg_indexed_tar" \
                             -i gam=${concat_job}:file \
                             -i chromosome="${chromosomes[$i]}" \
                             -i chromosome_length="${chromosome_lengths[$i]}" \
                             -i sample_name="$output_name" \
                             --name "call ${chromosomes[$i]}" \
                             -y --brief)
        vcf_in="$vcf_in -i in=${vg_call_job}:vcf"
    done

    # schedule concatenation of final VCF
    swiss_army_knife=$(dx find data --project "Developer Applets" --name "swiss-army-knife" --folder / --brief)
    vcf_job=$(dx run $swiss_army_knife --instance-type=mem2_hdd2_x2 \
                    -i cmd="(find . -name '*.vcf.gz' | sort -V | xargs -n 9999 --verbose bcftools concat \
                                | bgzip -c > /tmp/tmp.vcf.gz) && mv /tmp/tmp.vcf.gz ${output_name}.vcf.gz" \
                    $vcf_in --name "bcftools concat" -y --brief)

    #dx-jobutil-add-output vcf --class=jobref "${vcf_job}:out.0"
    # stupid coercion
    nop_job=$(dx run file_concatenator -i files=${vcf_job}:out.0 -i output_filename="${output_name}.vcf.gz" --name "nop" -y --brief --instance-type=mem2_hdd2_x2)
    dx-jobutil-add-output vcf --class=jobref ${nop_job}:file
}

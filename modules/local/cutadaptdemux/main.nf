#!/usr/bin/env nextflow
process CUTADAPTDEMUX {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/03/03cf0da4cd89cd348a329cca7bf989534ecd595979aab6de9350c3d59e7b9e4f/data':
        'community.wave.seqera.io/library/cutadapt:4.1--6047187d8e742a75' }"

    input:
    tuple val(meta), path(reads), path(barcodesheet)

    output:
    tuple val(meta), path("${prefix}.*.fastq.gz"), path("${prefix}.log"), emit: demux
    tuple val("${task.process}"), val('cutadapt'), eval("cutadapt --version"), topic: versions, emit: versions_cutadapt

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    args = task.ext.args ?: ""
    """
    # Extract info from barcodesheet
    G_OPTIONS=""
    while IFS=, read -r barcode sequence database dbname; do
        if [ "\$barcode" != "barcode" ]; then
            G_OPTIONS+="-g \$dbname=\$sequence "
        fi
    done < ${barcodesheet}

    # Run cutadapt
    cutadapt -e 3 --rc --action none --cores ${task.cpus} --discard-untrimmed \\
        ${args} \\
        \$G_OPTIONS \\
        -o ${prefix}.{name}.fastq.gz \\
        ${reads} | tee -a ${prefix}.log
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    args = task.ext.args ?: ""
    """
    echo $args
    
    touch sample.database.fastq.gz
    touch sample.log
    """
}
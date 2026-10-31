#!/usr/bin/env nextflow
process COUNTREADS {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/92/92dd7be87bec559f7660420797f82e321b77cbccd0b560a2bb1376d7b2d4fde1/data':
        'community.wave.seqera.io/library/pandas_python:072e5ad805444203' }"

    input:
    tuple val(meta), path(dlog), path(fastqs), path(barcodesheet)

    output:
    tuple val(meta), path("counts.tsv"), emit: counts

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    args   = task.ext.args ?: ""
    def fastq_files = fastqs.collect { fq -> "'${fq}'" }.join(", ")
    """
python << 'PYCODE'
import pandas as pd
import re
import os

bdf = pd.read_csv('${barcodesheet}')

# Prepare a list for counts
counts_data = []
    
files   = [${fastq_files}]

for index, row in bdf.iterrows():
    sequence = row['sequence']
    dbname = row['dbname']

    for fq in files:
        filename = os.path.basename(fq).split('.')[0]
        if (dbname == os.path.basename(fq).split('.')[1]):
            with open("${dlog}", 'r') as f:
                content = f.read()
            pattern = fr'Sequence: {sequence}.*?Trimmed: (\\d+) times'
            match = re.search(pattern, content, re.DOTALL)
            count = match.group(1) if match else '0'
            counts_data.append({'file': filename, 'count': int(count), 'dbname': dbname})
        else:
            continue

# Create dataframe and save to TSV
counts_df = pd.DataFrame(counts_data)
counts_df.to_csv('counts.tsv', sep='\\t', index=False)
PYCODE
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    args   = task.ext.args ?: ""
    """
    echo $args
    
    touch counts.tsv
    """
}
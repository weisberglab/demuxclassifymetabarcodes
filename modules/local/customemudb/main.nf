process CUSTOMEMUDB{
    label 'process_low'
    tag { "${db_name}" }

    publishDir "${params.emudbdir}", mode: 'copy'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/92/92dd7be87bec559f7660420797f82e321b77cbccd0b560a2bb1376d7b2d4fde1/data':
        'community.wave.seqera.io/library/emu_osfclient_python:20d5fe33c36819a6' }"

    input:
    tuple val(db_name), path(database_dir)

    output:
    path("emu_${db_name}"), emit: db

    script:
    seq2tax_map_tsv = "${database_dir}/kraken2/seqid2taxid.map"
    names_nodes_dmp_dir = "${database_dir}/kraken2/taxonomy"
    db_fasta = "${database_dir}/kraken2/library/*.fna"
    """
    emu build-database emu_${db_name} --sequences ${db_fasta} --seq2tax ${seq2tax_map_tsv} --ncbi-taxonomy ${names_nodes_dmp_dir}
    """
}
process FETCHEMUDB{
    label 'process_low'
    
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/92/92dd7be87bec559f7660420797f82e321b77cbccd0b560a2bb1376d7b2d4fde1/data':
        'community.wave.seqera.io/library/emu_osfclient_python:20d5fe33c36819a6' }"

    input:
    val(db)

    output:
    path("${db}_prebuilt"), emit: db
    tuple val("${task.process}"), val('osfclient'), eval("osfclient --version"), topic: versions, emit: versions_emu

    script:
    """
    osf -p 56uf7 fetch osfstorage/emu-prebuilt/${db}.tar

    mkdir ${db}_prebuilt
    mv ${db}.tar ${db}_prebuilt
    cd ${db}_prebuilt
    tar -xvf ${db}.tar
    cd ..
    """

    stub:
    def args = task.ext.args ?: ""
    """
    echo $args

    mkdir customdb_prebuilt
    """
}
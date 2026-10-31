process COMBINEANDPLOTBRACKEN{
    label 'process_low'
    tag "${db_name}"

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/50/509a6ac36238e3f717ab84202f4db14d0e9fa24241a1a354e1a6736f80eb45a8/data'
        : 'community.wave.seqera.io/library/pandas_python:072e5ad805444203'}"

    input:
    tuple val(db_name), path(bracken_tables), path(db)
    path(rmdfile)
    path(combine)

    output:
    tuple val("${db_name}"), path("combined.top20.${db_name}.bracken.csv") , emit: csv
    tuple val("${db_name}"), path("top20.all.${db_name}.bracken_plot.html"), emit: html

    script:
    """
        # Get top20 of each file
        mkdir -p files
        for f in *.tsv; do
            if [ -e "\$f" ]; then
                head -n 21 \${f} > top20.\${f}
            fi
        done

        # Combine files
        python ${combine} --files top20.* --output combined.top20.${db_name}.bracken.csv

        Rscript -e "rmarkdown::render('bracken_plot.Rmd', params=list(myinfile='combined.top20.${db_name}.bracken.csv'))"
        mv bracken_plot.html top20.all.${db_name}.bracken_plot.html

    """

    stub:
    """
    touch combined.top20.db.bracken.csv
    touch top20.all.db.bracken_plot.html
    """

}
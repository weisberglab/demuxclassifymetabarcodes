process SANKEYPLOTBRACKEN {
    label 'process_medium'
    tag { "${db_name}" }

    publishDir { "${params.outdir}/${params.name}/${db_name}/final_out" }

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22add319d95cd4e0e87b6c1a174da4ff72a8240a95f477236e0096904b90de57/data'
        : 'community.wave.seqera.io/library/matplotlib_pandas_plotly:5e5d0a32da93056b'}"

    input:
    tuple val(db_name), path(bracken_tables), path(db)
    val(run_name)

    output:
    path("combined_bracken_sankey.${db_name}.html"), emit: html
    tuple val("${task.process}"), val('plotly'), eval('python -c "import plotly; print(plotly.__version__)"'), topic: versions, emit: versions_plotly

    script:
    pyfile = "${moduleDir}/bracken_to_sankey.py"
    plotfile = "${moduleDir}/plot_sankey.py"
    combinefile = "${moduleDir}/combine_sankey.py"
    """
    for f in *.tsv; do
        if [ -e "\$f" ]; then
            head -n 21 \${f} > top20.\${f}
            base=\$(basename "\$f")
            name="\${base%.*}"
            python ${pyfile} --bracken top20.\${f} \\
                --taxonomy ${db}/kraken2/taxonomy \\
                --min_count 1000 \\
                --output_prefix \$name.${db_name}
            python ${plotfile} --db_name ${db_name} --run_name \$name --input \$name.${db_name}.plot_data.csv
        fi
    done

    python ${combinefile} --input_htmls *.sankey_plot.html --output combined_bracken_sankey.${db_name}.html
    rm -rf *.sankey_plot.html
    rm -rf *.plot_data.csv
    """

    stub:
    def args = task.ext.args ?: ""
    """
    echo $args

    touch combined_bracken_sankey.db.html
    """
}
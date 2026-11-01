process SANKEYPLOTEMU {
    label 'process_low'
    cache false
    tag { "${db_name}" }

    publishDir { "${params.outdir}/${params.trace_report_suffix}_run/${db_name}_output" }

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22add319d95cd4e0e87b6c1a174da4ff72a8240a95f477236e0096904b90de57/data':
        'community.wave.seqera.io/library/matplotlib_pandas_plotly:5e5d0a32da93056b' }"

    input:
    tuple val(db_name), path(emu_reports, stageAs: "reps/*"), path(emu_assignment_reports, stageAs: "rads/*")
    val(run_name)
    path(plotfile)
    path(combinefile)

    output:
    path("combined_emu_sankey.*.${db_name}.html")        , emit: sankey_html
    tuple path(emu_reports), path(emu_assignment_reports), emit: emu_reports

    script:
    def args = task.ext.args ?: ""
    """
    python - <<'PYCODE'
    import pandas as pd
    import sys
    from pathlib import Path

    db_name = "$db_name"
    reps = Path("reps")
    rads = Path("rads")

    # Convert relative abundances tables to htmls
    for file in [f for f in reps.iterdir() if not f.is_dir()]:
        df = pd.read_csv(file, sep='\\t')
        df.to_html(f"{file.name.removesuffix('_rel-abundance.tsv')}.table.html")

    for file in [f for f in rads.iterdir() if not f.is_dir()]:
        name = file.name.removesuffix("_read-assignment-distributions.tsv")
        print(f"Working with file: {name}")

        df1 = pd.read_csv(file, sep="\\t", header=0, index_col=0).fillna(0)
        df1.index.name = "read"
        df1 = df1.copy()

        df_best = pd.DataFrame({
            "tax_id": df1.idxmax(axis=1),
            "max_probability_avg": df1.max(axis=1),
        }).groupby("tax_id").mean()

        # find matching abundance report
        for f in [fi for fi in reps.iterdir() if not fi.is_dir()]:
            name1 = Path(f).name.removesuffix("_rel-abundance.tsv")

            if name == name1:
                df = pd.read_csv(f, sep="\\t")
                print("Columns:", df.columns.tolist())
                print(df.head())
                # drop unmapped / placeholders if needed
                df = df[df['tax_id'] != 'unmapped']

                # get top 20 abundances
                df = df.sort_values(by=['abundance'], ascending=False).head(20)

                # Merge probabilities into df
                df = df.merge(df_best, on='tax_id', how='left')

                # fill empty taxonomic levels with the last known value
                tax_levels = ['superkingdom','phylum','class','order','family','genus','species']
                df[tax_levels] = df[tax_levels].ffill(axis=1)

                # create Sankey links
                rows = []

                for _, r in df.iterrows():
                    prev = None
                    for lvl in tax_levels:
                        if pd.notna(r[lvl]):
                            if prev is not None:
                                # Format target: add probability only for the deepest level (species)
                                if lvl == 'species' and pd.notna(r.get('max_probability_avg')):
                                    target = f"{lvl.capitalize()}: {r[lvl]} (prob: {r['max_probability_avg']:.3f})"
                                else:
                                    target = f"{lvl.capitalize()}: {r[lvl]}"

                                # source = prev_level, target = current level, value = abundance
                                rows.append({
                                    'source': f"{prev[0]}: {prev[1]}",
                                    'target': target,
                                    'value': r['abundance']
                                })
                            prev = (lvl.capitalize(), r[lvl])

                # convert to DataFrame
                sankey_df = pd.DataFrame(rows)

                # sum duplicates (if multiple rows go from same source->target)
                if not sankey_df.empty:
                    sankey_df = sankey_df.groupby(['source','target'], as_index=False).sum()

                # write to CSV
                sankey_df.to_csv(f"emu_sankey.{name1}.{db_name}.plot_data.csv", index=False)

    PYCODE

    # individual sankeys
    for f in emu_sankey.*.${db_name}.plot_data.csv; do
        [ -e "\$f" ] || continue

        name="\${f#emu_sankey.}"
        name="\${name%.${db_name}.plot_data.csv}"

        python ${plotfile} --db_name ${db_name} --run_name "\${name}" --input "\${f}"
        
    done

    # combine sankeys
    python ${combinefile} --input_htmls *.sankey_plot.html --input_emu *_rel-abundance.tsv --output combined_emu_sankey.${run_name}.${db_name}.html
    rm -rf emu_sankey.*.html
    rm -rf *.plot_data.csv
    """
    
    stub:
    def args = task.ext.args ?: ""
    """
    echo $args
    
    touch combined_emu_sankey.${run_name}.${db_name}.html
    """
}
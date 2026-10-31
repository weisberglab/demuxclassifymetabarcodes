process FORMATEMUREADASSIGNMENTS{
    label 'process_medium'
    tag "${dbname}"

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/22/22add319d95cd4e0e87b6c1a174da4ff72a8240a95f477236e0096904b90de57/data':
        'community.wave.seqera.io/library/matplotlib_pandas_plotly:5e5d0a32da93056b' }"

    input:
    tuple val(dbname), path(ras), path(kdb)

    output:
    tuple val(dbname), path("*.*.ra_avgs.tsv"), path(kdb), emit: avgs
    tuple val("${task.process}"), val('emu'), eval("python -c 'import matplotlib; print(matplotlib.__version__)' | head -n 1"), topic: versions, emit: versions_emu

    script:
    """
python << 'PYCODE'
import pandas as pd

for file in ["${ras}"]:
    df = pd.read_csv(file, sep="\\t", header=0, index_col=0).fillna(0)
    df.index.name = "read"
    df = df.copy()

    df_best = pd.DataFrame({
        "read": df.index,
        "taxid": df.idxmax(axis=1),
        "max_probability_avg": df.max(axis=1),
    }).reset_index(drop=True).drop(columns=['read']).groupby('taxid').mean()

    df_best.to_csv(f'{file.split('.')[0]}.${dbname}.ra_avgs.tsv', sep='\\t')

PYCODE
    """

    stub:
    def args = task.ext.args ?: ''
    """
    echo $args

    touch sample.db.ra_avgs.tsv
    """
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FILEPARSER                } from '../subworkflows/local/fileparser/main.nf'

include { CUTADAPTDEMUX             } from '../modules/local/cutadaptdemux/main.nf'
include { COUNTREADS                } from '../modules/local/countreads/main.nf'

include { KRAKEN2_KRAKEN2           } from '../modules/nf-core/kraken2/kraken2/main.nf'
include { BRACKEN_BRACKEN           } from '../modules/nf-core/bracken/bracken/main.nf'
include { COMBINEANDPLOTBRACKEN     } from '../modules/local/combineandplotbracken/main.nf'
include { SANKEYPLOTBRACKEN         } from '../modules/local/sankeyplotbracken/main.nf'

include { EMU_ABUNDANCE             } from '../modules/nf-core/emu/abundance/main.nf'
include { CUSTOMEMUDB               } from '../modules/local/customemudb/main.nf'
include { FETCHEMUDB                } from '../modules/local/fetchemudb/main.nf'
include { SANKEYPLOTEMU             } from '../modules/local/sankeyplotemu/main.nf'
include { FORMATEMUREADASSIGNMENTS  } from '../modules/local/formatemureadassignments/main.nf'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow DEMUXCLASSIFYMETABARCODES {

    take:
    ch_input

    main:
    ch_versions = channel.empty()
    ch_parsed = FILEPARSER(ch_input)
    ch_meta_fasta = ch_parsed.ch_usable

    // create dbname to kraken db map
    def dbname_db = [:]
    new File(params.barcodesheet).eachLine { line -> 
        if (!line.startsWith('barcode')) {
            def parts = line.split(',')
            dbname_db[parts[3]] = parts[2] // db name = db location
        }
    }

    //
    // LOCAL MODULE: CUTADAPT AND DEMULTIPLEX
    //
    
    ch_barcodesheet = channel.fromPath(params.barcodesheet)
    cut = CUTADAPTDEMUX( ch_meta_fasta.combine(ch_barcodesheet) )
    
    // cut.demux: meta, fastqs (list), log
    // Create a channel of [meta, demuxed_fastq] for each demuxed file
    ch_demuxed_reads = cut.demux.map{ meta, fastqs, _log ->
        tuple(meta, fastqs)
    }

    // For COUNT_READS
    count = COUNTREADS( 
                    cut.demux.map{ meta, fastqs, log -> tuple(meta, log, fastqs) }
                    .combine(ch_barcodesheet)
                )

    def db_counts = [:]

    // Combine counts with demuxed reads for filtering
    ch_filtered_reads = count.counts
        .join(ch_demuxed_reads)
        .map { meta, counts_file, fastqs ->
            tuple(meta, counts_file, [fastqs])
        }
        .flatMap { meta, counts_file, fastqs ->
            counts_file.eachLine { line ->
                if (!line.startsWith('file')) {
                    def parts = line.split('\t')
                    def db = parts[2]
                    def count = parts[1].toInteger()
                    db_counts[db] = count
                }
            }

            fastqs.flatten().collect { fq ->
                def db_name = fq.name.tokenize('.')[-3]
                def count = db_counts[db_name] ?: 0
                if (count >= params.min_reads) {
                    tuple(meta, fq, db_name)
                } else {
                    // println "Skipping Emu and Kraken/Bracken on file ${meta.id} for database ${db_name}: not enough counts (threshold: ${params.min_reads})"
                    null
                }
            }.findAll { fq -> fq != null }
        }

/*

    // Prepare for Kraken: [meta, fastq, db]
    ch_kraken_input = ch_filtered_reads.map{ meta, fastq, dbname ->
        def dbloc = dbname_db[dbname]
        tuple(meta, fastq, dbloc)
    }

    //
    // NF-CORE MODULE: KRAKEN2
    //

    ch_kraken_out = KRAKEN2_KRAKEN2(
        ch_kraken_input,
        ch_kraken_input.map{ it -> params.save_fastqs},
        ch_kraken_input.map{ it -> params.save_areads}
    )

    ch_kraken_reports   = ch_kraken_out.report

    // Filter Kraken reports: only pass to Bracken if >= min_classified_reads are classified
    ch_filtered_kraken = ch_kraken_reports.filter { meta, report, db ->
        def classified_count = 0
        report.readLines().each { line ->
            def parts = line.trim().split()
            // Look for root (R) rank line which contains total classified reads
            if (parts.size() >= 4 && parts[3] == 'R' && parts[0] != '100.00') {
                classified_count = parts[1].toInteger()
            }
        }
        
        if (classified_count < params.min_classified_reads) {
            // log.warn "Skipping Bracken on file ${meta.id} for database ${db.baseName}: only ${classified_count} classified reads (threshold: ${params.min_classified_reads})"
            return false
        }
        return true
    }

    //
    // NF-CORE MODULE: BRACKEN
    //

    brackenout = BRACKEN_BRACKEN(
        ch_filtered_kraken // tuple(meta, reports, db)
    ) 

    breports = brackenout.reports
                    .map { meta, reports, db ->
                        tuple(db.baseName, tuple(meta, reports), db)
                    }
                    .groupTuple()
                    .map { db_name, tuples, dbs ->
                        def all_reports = tuples.collect{it[1]}
                        tuple(db_name, all_reports, dbs[0])  // Take first db since all are the same
                    }

    rmdfile = file("/nfs7/BPP/Weisberg_Lab/projects/PlantClinic_diagnostics/nf-core-tests/DMACMC/weisberg_lab-plantclinicdemuxclassify/modules/local/combineandplot/bracken_plot.Rmd")
    combine = file("/nfs7/BPP/Weisberg_Lab/projects/PlantClinic_diagnostics/nf-core-tests/DMACMC/weisberg_lab-plantclinicdemuxclassify/modules/local/combineandplot/combine_bracken_outputs.py")

    cpbout = COMBINE_AND_PLOT_BRACKEN(
        breports, // tuple(db_name, all_reports, db)
        breports.map{ it -> rmdfile },
        breports.map{ it -> combine }
    )

    SANKEY_PLOT(
        breports, // tuple(db_name, all_reports, db)
        breports.map{ it -> params.name }
    )
*/

    //
    //  GITHUB MODULE: EMU
    //

    ch_emu_dbs    = ch_parsed.ch_dbs

    // create dbname to emu db map
    def emudbname = [:]
    ch_emu_dbs.collect().map{ list ->
        list.each { dbloc ->
            def parts = dbloc.name.tokenize('_') // each path in dbloc should be ['emu', 'dbname']
            emudbname[parts[1]] = dbloc // db name, db
        }
        emudbname
    }

    // Prepare and run EMU
    ch_emu_input = ch_filtered_reads.map { meta, fq, db_name ->
            def dbloc = emudbname[db_name]
            tuple(meta, fq, dbloc, db_name)
        }.multiMap { meta, fq, dbloc, db_name ->
            files: tuple(meta, fq)
            dbs: tuple(dbloc, db_name)
        }

    emu_out = EMU_ABUNDANCE( 
        ch_emu_input.files, // tuple(meta, fq)
        ch_emu_input.dbs    // tuple(db_location, db_name)
        )    

    //
    // LOCAL MODULES: PLOTTING
    //

    // emu_out.report: tuple(meta, report.tsv, dbname, db)
    // emu_out.assignment_report: tuple(meta, areport.tsv)

    // mix output channels, group by meta, then group by dbname
    emu_sankey = emu_out.report
                    .join(emu_out.assignment_report) // tuple(meta, reports, dbname, dbloc, areports)
                    .map{ _meta, reports, dbname, _db, areports -> tuple(dbname, reports, areports)}.groupTuple(by: 0) 

    SANKEYPLOTEMU(
        emu_sankey, // tuple(dbname, all_reports_for_that_db, all_read_assignments_for_that_db)
        channel.value(params.trace_report_suffix),
        channel.value(file("${projectDir}/modules/local/sankeyplotemu/plot_sankey.py")),
        channel.value(file("${projectDir}/modules/local/sankeyplotemu/combine_sankey.py"))
    )

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

#!/usr/bin/env nextflow

include { CUSTOMEMUDB       } from '../../../modules/local/customemudb'

workflow FILEPARSER{

    take:
    ch_input

    main:
    // Check if ch_input contains a directory of files rather than one file, or if it contains a comma-separated list
    if (params.input.contains(',')) {
        input_paths = params.input.split(',').collect{input -> input.trim()}
    } else {
        input_paths = [ params.input ]
    }

    ch_input = channel.from(input_paths).map { f -> file(f) }
    
    ch_files = ch_input.flatMap { f ->
        if (f.isDirectory()) {
            f.listFiles().collect{ df -> file(df) }
        } else {
            return [ f ]
        }
    }

    // Check file types and split them into channels
    ch_filetype = ch_files.map { f ->
        def filename = f.name
        def type = 'unknown'

        if (filename.endsWith('.fasta') || filename.endsWith('.fa') || filename.endsWith('.fna') || filename.endsWith('.fastq')) {
            type = 'fasta'
        } else if (filename.endsWith('.fasta.gz') || filename.endsWith('.fa.gz') || filename.endsWith('.fna.gz') || filename.endsWith('.fastq.gz')) {
            type = 'gunzip'
        } else {
            type = 'unknown'

        }

        tuple(f, type)
    }

    // Split channel by filetype
    ch_usable = ch_filetype
            .filter{ _f, type -> type != "unknown" }
            .map{ f, _type -> 
                def fname = ''
                if (f.name.endsWith('.gz')) {
                    fname = f.name.tokenize(".")[0]
                } else {
                    fname = f.baseName
                }
                tuple([id: fname, single_end: true], f)
            }

    // Emu database input setup
    ch_unmade_emu_dbs = channel.of(
        new File(params.barcodesheet).eachLine { line -> 
            if (!line.startsWith('barcode')) {
                def parts = line.split(',')
                // checking emu database existence
                if ( !file("${params.emudbdir}/emu_${parts[3]}").exists() ) {
                    return tuple(parts[3], parts[2])
                } else {
                    return null
                }
            }
        }
    ).filter { f -> f != null }

    outs = CUSTOMEMUDB( ch_unmade_emu_dbs )

    ch_dbs = channel.from( [params.emudbdir] ).map{ f -> file(f) }.flatMap{ f -> f.listFiles().collect{ cf -> file(cf) }}.mix( outs.db )

    emit:
    ch_usable
    ch_dbs
}
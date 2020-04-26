#
# Author: Daniel E. Cook
#
import argparse
import strformat
import colorize
import tables
import hts
import strutils
import sequtils
import zip/gzipfiles
import hts

import src/fq_meta
import src/fq_count
import src/fq_dedup

import src/insert_size
import src/read_count
import src/contamination

import src/vcf2fasta
import src/vcf2tsv
import src/vcf2json
import src/tajimas_d
import src/genome_iter
import src/phylo

import src/utils/helpers

from posix import signal, SIG_PIPE, SIG_IGN
signal(SIG_PIPE, SIG_IGN)

const VERSION = "0.0.2"

proc get_vcf(vcf: string): string =
    if vcf == "STDIN":
        return "-"
    return vcf

var p = newParser("sc"):
    flag("--debug", help="Debug")
    help(fmt"Sequence data utilities (Version {VERSION})")
    command("fq-meta", group="FASTQ"):
        help("Output metadata for FASTQ")
        arg("fastq", nargs = -1, help="List of FASTQ files")
        option("-n", "--lines", help="Number of sequences to sample (n_lines) for qual and index/barcode determination", default = "100")
        flag("-t", "--header", help="Output the header")
        flag("-b", "--basename", help="Add basename column")
        flag("-a", "--absolute", help="Add column for absolute path") 
        run:
            if opts.header:
                echo output_header(fq_meta_header, opts.basename, opts.absolute)
            if opts.fastq.len > 0:
                for fastq in opts.fastq:
                    fq_meta.fq_meta(fastq, parseInt(opts.lines), opts.basename, opts.absolute)
    
    #########
    # FASTQ #
    #########

    command("fq-count", group="FASTQ"):
        help("Counts lines in a FASTQ")
        flag("-t", "--header", help="Output the header")
        flag("-b", "--basename", help="Add basename column")
        flag("-a", "--absolute", help="Add column for absolute path") 
        arg("fastq", nargs = -1, help = "Input FASTQ")
        run:
            if opts.header:
                echo output_header(fq_count_header, opts.basename, opts.absolute)
            elif opts.fastq.len == 0:
                quit_error("No FASTQ specified", 3)
            if opts.fastq.len > 0:
                for fastq in opts.fastq:
                    fq_count.fq_count(fastq, opts.basename, opts.absolute)

    command("fq-dedup", group="FASTQ"):
        help("Removes exact duplicates from FASTQ Files")
        arg("fastq", nargs = 1, help = "Input FASTQ")
        run:
            fq_dedup.fq_dedup(opts.fastq)

    #######
    # BAM #
    #######

    command("contamination", group="BAM"):
        help("Estimate contamination")
        arg("bam", nargs = 1, help = "Input BAM")
        arg("positions", help="Variant positions")
        run:
            contamination.cmd_contamination(opts.bam, opts.positions)

    command("insert-size", group="BAM"):
        help("Calculate insert-size metrics")
        option("-d", "--dist", default="", help = "Output raw distribution(s)")
        arg("bam", nargs = -1, help = "Input BAM")
        flag("-t", "--header", help="Output the header")
        flag("-b", "--basename", help="Add basename column")
        flag("-a", "--absolute", help="Add column for absolute path")        
        flag("-v", "--verbose", help="Provide additional information")
        run:
            if opts.header:
                echo output_header(insert_size_header, opts.basename, opts.absolute)
            elif opts.bam.len == 0:
                quit_error("No BAM specified", 3)
            if opts.bam.len > 0:
                for bam in opts.bam:
                    insert_size.cmd_insert_size(bam, opts.dist, opts.verbose, opts.basename, opts.absolute)

    command("read-count", group="BAM"):
        help("Generate read-counts")
        arg("bam", nargs = 1, help = "Input BAM")
        option("--positions", help="Output regions")
        run:
            read_count.cmd_read_count(opts.bam, opts.positions)


    #######
    # VCF #
    #######

    command("json", group="VCF"):
        help("Convert a VCF to JSON")
        arg("vcf", nargs = 1, help="VCF to convert to JSON")
        arg("region", nargs = -1, help="List of regions")
        option("-i", "--info", help="comma-delimited INFO fields; Use 'ALL' for everything", default="")
        option("-f", "--format", help="comma-delimited FORMAT fields; Use 'ALL' for everything", default="")
        option("-s", "--samples", help="Set Samples", default="ALL")
        flag("-p", "--pretty", help="Prettify result")
        flag("-a", "--array", help="Output as a JSON array instead of individual JSON lines")
        flag("-z", "--zip", help="Zip sample names with FORMAT fields (e.g. {'sample1': 25, 'sample2': 34})")
        flag("-n", "--annotation", help="Parse ANN Fields")
        flag("--pass", help="Only output variants where FILTER=PASS")
        flag("--debug", help="Debug")
        run:
            to_json(get_vcf(opts.vcf), opts.region, opts.samples, opts.info, opts.format, opts.zip, opts.annotation, opts.pretty, opts.array, opts.pass)

    command("tajima", group="VCF"):
        help("Calculate tajimas D")
        arg("vcf", nargs = 1, help="Calculate Tajima's D")
        arg("region", nargs = -1, help="List of regions")
        option("-w", "--window_size", default = "100000", help = "Window size")
        option("-s", "--step_size", default = "100000", help = "Step size")
        option("--sliding", default = "false", help = "Slide window")

        run:
            tajimas_d.calc_tajima(get_vcf(opts.vcf), opts.region)

    command("tsv", group="VCF"):
        help("Convert a VCF to TSV")
        arg("vcf", nargs = 1, help="VCF to convert to JSON")
        arg("region", nargs = -1, help="List of regions")
        option("-i", "--info", help="comma-delimited INFO fields", default="ALL")
        option("-f", "--format", help="comma-delimited FORMAT fields", default="ALL")
        option("-s", "--samples", help="Set Samples", default="ALL")
        flag("-n", "--annotation", help="Parse ANN Fields")
        flag("-l", "--long", help="Output in long format")
        flag("--pass", help="Only output variants where FILTER=PASS")
        flag("--debug", help="Debug")
        run:
            if opts.vcf.len == 0:
                quit_error("No VCF specified", 3)
            elif opts.vcf.len > 0:
                vcf2tsv(opts.vcf, opts.region, opts.samples, opts.info, opts.format, opts.long, opts.annotation, opts.pass)

    command("phylo", group="VCF"):
        help("Generate phylo files")
        arg("vcf", nargs = 1, help="VCF to convert to JSON")
        arg("region", nargs = -1, help="List of regions")
        run:
            vcf2phylo(get_vcf(opts.vcf), opts.region)
            

    command("iter", group="MULTI"):
        help("Generate genomic ranges for iteration from a BAM or VCF for parallel execution")
        arg("input", nargs = 1, help = "Input VCF or BAM")
        arg("width", default="10000", nargs = 1, help = "bp length; Set to 0 to list chromosomes")
        run:
            var width = helpers.sci_parse_int(opts.width)
            if width < 0:
                quit_error("Width must be greater than 0")
            if opts.input.endswith(".vcf.gz") or opts.input.endswith(".vcf") or opts.input.endswith(".vcf"):
                var v:VCF
                doAssert open(v, opts.input)
                genome_iter(v, width)
            else:
                var b:BAM
                doAssert open(b, opts.input)
                genome_iter(b, width)
    

# Check if input is from pipe
var input_params = commandLineParams()
if getFileInfo(stdin).id.device==0:
    if input_params.find("-") > -1:
       input_params[input_params.find("-")] = "STDIN"
    else:
        input_params.add("STDIN")

if input_params.len <= 1:
    input_params.add("-h")
    p.run(input_params)
else:
    try:
        p.run(input_params)
    except UsageError as E:
        input_params.add("-h")
        stderr.write_line "Error".bgWhite.fgRed & fmt": {E.msg}".fgRed
        if input_params.find("--debug") > -1:
            p.run(input_params)
    except Exception as E:
        if commandLineParams().find("--debug") > -1:
            stderr.write_line "Error".bgWhite.fgRed & fmt": {E.msg}".fgRed
            raise
        else:
            if E.msg != "errno: 32 `Broken pipe`":
                quit_error(E.msg)

proc ctrlc() {.noconv.} =
  echo "Ctrl+C fired!"
  quit_error("")

setControlCHook(ctrlc)
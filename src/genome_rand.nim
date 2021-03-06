# Generates a random site
import regex
import hts
import math
import random/urandom, random/mersenne
import alea
import tables
import random
import sequtils
import strformat
import strutils
import algorithm
import utils/bed

randomize()

type
    genome* = ref object
        chrom_table*: Table[string, Region] # region --> length
        cum_length*: int                    # Sum of lengths
        chrom_weights*: seq[float]          # weighted lengths
        chrom_bins*: seq[float]
  
    site* = ref object
        chrom*: string
        start*: int
        stop*: int
        one*: int

proc `$`*(s: site): string =
    return @[s.chrom, $(s.start + s.one), $(s.stop + s.one)].join("\t")


proc region*(s: site): string = 
    return fmt"{s.chrom}:{s.start}-{s.stop}"

#=========#
#   BED   #
#=========#

# proc gen_chrom_table(f: Bed, pattern: string): Table[string, Region] =
#     if bed != "":
#         for region in bed.iter_bed():
#             if is_some(match(region.chrom, re(pattern))):
#                 result[$region] = region


#=========#
#   FAI   #
#=========#

proc gen_chrom_table(f: Fai, bed: string, pattern: string): Table[string, Region] =
    # Generate a table of chrom -> chrom_len
    # For bed files this is the sum of regions on that chrom
    var m_group: regex.RegexMatch
    let sre = regex.re(pattern)
    if bed != "":
        for region in bed.iter_bed():
            if pattern == "" or regex.match(region.chrom, sre, m_group):
                result[$region] = region
    else:
        for i in 0..<f.len:
            if pattern == "" or  regex.match(f[i], sre, m_group):
                var reg = Region(chrom: f[i],
                                start: 0,
                                stop: f.chrom_len(f[i]))
                result[$reg] = reg

#=========#
#   BAM   #
#=========#

proc gen_chrom_table(bam: BAM, bed: string, pattern: string): Table[string, Region] =
    # Generate a table of chrom -> chrom_len
    # For bed files this is the sum of regions on that chrom
    var m_group: regex.RegexMatch
    if bed != "":
        for region in bed.iter_bed():
            if pattern == "" or regex.match(region.chrom, regex.re(pattern), m_group):
                result[$region] = region
    else:
        for contig in bam.hdr.targets:
            if pattern == "" or regex.match(contig.name, regex.re(pattern), m_group):
                var reg = Region(chrom: contig.name,
                                start: 0,
                                stop: contig.length.int)
                result[$reg] = reg

#=========#
#   VCF   #
#=========#

proc gen_chrom_table(vcf: VCF, bed: string, pattern: string): Table[string, Region] =
    # Generate a table of chrom -> chrom_len
    # For bed files this is the sum of regions on that chrom
    var m_group: regex.RegexMatch
    if bed != "":
        for region in bed.iter_bed():
            if pattern == "" or regex.match(region.chrom, regex.re(pattern), m_group):
                result[$region] = region
    else:
        for contig in vcf.contigs:
            if pattern == "" or regex.match(contig.name, regex.re(pattern), m_group):
                var reg = Region(chrom: contig.name,
                                start: 0,
                                stop: contig.length.int)
                result[$reg] = reg

#==================#
#   genome table   #
#==================#

proc cum_length(chr_tbl: Table[string, Region]): int =
    # Calculate the cumulative length of all chromosomes/regions
    return toSeq(chr_tbl.values()).mapIt( it.len ).foldl( a + b )

proc chrom_weights(chr_tbl: Table[string, Region]): seq[float] =
    # Calculate weight of each chromosome/region
    let cum_length = chr_tbl.cum_length()
    return toSeq(chr_tbl.values()).mapIt( it.len / cum_length )

proc chrom_bins(chr_tbl: Table[string, Region]): seq[float] =
    # Generate a sequence of bins based on chrom lengths
    var chrom_weights = chr_tbl.chrom_weights()
    var prob_bins = new_seq[float](chrom_weights.len)
    prob_bins[0] = chrom_weights[0]
    for i in 1..chrom_weights.len - 1:
        prob_bins[i] = prob_bins[i-1] + chrom_weights[i]
    return prob_bins

proc rand_region*(g: genome): Region = 
    let region_select = g.chrom_bins.lowerBound(rand(1.0))
    return toSeq(g.chrom_table.values)[region_select]

proc rand_pos*(g: genome, region: Region): int =
    let r = g.chrom_table[$region]
    return rand(r.len) + r.start

proc range_iter*(range_spec: string): iterator:int = 
    #[Parses range specification

    1,5 --> Normal/Gaussian distr N(1,5)
    1-5 --> Uniform distr U(1,5)
    5 --> Constant

    1 is subtracted to make distributions relative to a base
    ]#
    var rng = wrap(initMersenneTwister(urandom(16)))
    if range_spec.contains(","):
        var
            mu: float
            sigma: float
        (mu, sigma) = range_spec.split(",", 1).mapIt( it.parseFloat() )
        let g = gaussian(mu, sigma-1)
        return iterator:int =
            while true:
                yield rng.sample(g).int
    elif range_spec.contains("-"):
        var
            start: float
            stop: float
        (start, stop) = range_spec.split("-", 1).mapIt( it.parseFloat() )
        let g = uniform(start-1, stop-1)
        return iterator:int =
            while true:
                yield rng.sample(g).round().int
    else:
        let r = range_spec.parseInt()
        return iterator:int = 
            while true:
                yield r

proc overlaps(x: Region, a: int, b: int): bool =
    return a >= x.start and b >= x.start and
           a <= x.stop and b <= x.stop

iterator random_site*(g: genome, n: int, rng_distribution: iterator, one = 0.int): site = 
    #[
        Generates a random site based on a given rng_distribution distribution
    ]#
    var i = if n <= 0: -1 else: 0
    while i < n:
        var 
            region: Region
            start: int
            stop: int
        while true:
            region = g.rand_region()
            start = rand_pos(g, region)
            stop = start + rng_distribution()
            if g.chrom_table[$region].overlaps(start, stop) == false:
                # Check that end position does not extend
                # beyond end of region
                continue
            # Swap direction of rng_distribution in some cases
            if stop < start and start >= 0:
                (start, stop) = (stop, start)
            if start < 0 or stop < 0:
                continue
            else:
                break
        # Handle infinite iteration
        if n > 0:
            i += 1
        yield site(chrom: region.chrom,
                   start: start,
                   stop: stop,
                   one: one)

proc get_genome*[T: Fai | BAM | VCF](f: T, bed = "", pattern = ""): genome =
    # Constructs chrom bins for randomly sampling from genome
    var g = genome()
    let chrom_table = f.gen_chrom_table(bed, pattern)
    g.chrom_table = chrom_table
    g.cum_length = chrom_table.cum_length()
    g.chrom_weights = chrom_table.chrom_weights()
    g.chrom_bins = chrom_table.chrom_bins()
    return g

proc genome_rand*(f: Fai, n_sites: int, bed: string, range_s: string, pattern: string, one: int) =
    var genome_ref = f.get_genome(bed, pattern)
    for i in genome_ref.random_site(n_sites, range_iter(range_s), one):
        if i.start > 0:
            echo i, "\t", f.get(i.chrom, i.start, i.stop)
        else:
            echo i, "\t", f.get(i.chrom, i.start, i.stop)[0]

proc genome_rand*(b: BAM, n_sites: int, bed: string, range_s: string, pattern: string, one: int) =
    var genome_ref = b.get_genome(bed, pattern)
    for i in genome_ref.random_site(n_sites, range_iter(range_s), one):
        echo i

proc genome_rand*(v: VCF, n_sites: int, bed: string, range_s: string, pattern: string, one: int) =
    var genome_ref = v.get_genome(bed, pattern)
    for i in genome_ref.random_site(n_sites, range_iter(range_s), one):
        echo i

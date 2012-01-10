#!/usr/local/bin/perl
# $Id: gmap_output_to_model_gff.pl 542 2007-07-24 18:25:31Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# To use this script, first align the submitted structural annotation ( as cDNA seqs) against the reference
# genome using GMAP using the -S and -S -T options. These GMAP alignment files are then parsed
# and the community annotation models are output as GFF2 and are ready to load into the GFF DB

use strict;
use warnings;
use DBI;
use Getopt::Long;
use lib '../lib/';
use CA::CDBI;
use CA::loci;

my $gmap_sum = q{};
my $gmap_trunc = q{};
my $user_id = 0;
my $family_id = 0;

GetOptions('gmap_sum=s' => \$gmap_sum, 'gmap_trunc=s' => \$gmap_trunc, 'user_id=i' => \$user_id, 'family_id=i' => \$family_id);
 
unless ($gmap_sum && $gmap_trunc && $user_id && $family_id) {
    die ("Usage: perl gmap_sum_2_gff.pl --gmap_sum=gmap_summary_file  --gmap_trunc =gmap_trunc_sum_file  --user_id=user_id --family_id=family_id\n");
}


my %trans;
open (my $trunc_file, "<", $gmap_trunc) or die ("Error: $! \n");
TRUNC_ALIGN: while(<$trunc_file>){
    if (/^>/) {
        my $def_line = $_;
        my ( $gene_name ) = $def_line =~ m/^>(\S+)\s+/;
        while (<$trunc_file>) {
            my $line = $_;
            if ($line =~ m/\bPath\b/) {
                my ($trans_start, $trans_stop) = $line =~ m/Path \d+: query (\d+)--(\d+) \(/;
                $trans{$gene_name} = [$trans_start, $trans_stop];
                next TRUNC_ALIGN;
            } else {
                next;
            }
        }
    }
}
close($trunc_file);

open(my $file, "<", $gmap_sum) or die ("Error: $! \n");
while (<$file>) {
    if (/^>/) {
        parse_sum_align($file, $_);
    }
}
close($file);

sub parse_sum_align{
    my ($file, $def_line) = @_;
    my ( $gene_name ) = $def_line =~ m/^>(\S+)\s+/;
    my ($query_start, $query_end, $chr, $genomic_end5, $genomic_end3, $num_exons);
  ALIGN_SUM: while (<$file>){
        my $line = $_;
        if ($line =~ m/Path \d: query/) {
            $line =~ s/,//g;
            ($query_start, $query_end, $chr, $genomic_end5, $genomic_end3) = $line =~ m/Path \d: query (\d+)--(\d+) \(\d+ bp\) => chr (Chr\d+)_v4:(\d+)--(\d+) \(/;
        } elsif ($line =~ m/Number of exons/) {
            ($num_exons) = $line =~ m/Number of exons: (\d+)/;
        } elsif ($line =~ m/\bAlignment\b/) {
            <$file>;            #read line into void context
            last ALIGN_SUM;
        } else {
            next ALIGN_SUM;
        }
    }
    #print join ("\t", ($gene_name, $query_start, $query_end, $chr, $genomic_end5, $genomic_end3, $num_exons, $trans_start, $trans_stop))."\n";
    my @hsps;
  ALIGN_HSPS: for (1..$num_exons){
        my $hsp_line = <$file>;
        my @exons = $hsp_line =~ m/[+-]Chr\d+_v4:(\d+)-(\d+)\s+\((\d+)-(\d+)\)/;
        #print "Exons:".join ("\t", @exons)."\n";
        push (@hsps, [@exons]);
    }
	
    my $strand = $hsps[0]->[0] < $hsps[0]->[1] ? "+" : "-";
    my $span_start =  $genomic_end5 < $genomic_end3 ? $genomic_end5 : $genomic_end3;
    my $span_end = $genomic_end5 < $genomic_end3 ? $genomic_end3 : $genomic_end5;
    my $trans_start = $trans{$gene_name}->[0];
    my $trans_stop = $trans{$gene_name}->[1];
    unless ($trans_start && $trans_stop) {
        die "Translation start and stop not found for $gene_name \n";
    }
	
    #fetch the locus_id and description

    my ( $locus ) = CA::loci->search( user_id => $user_id, family_id => $family_id, gene_name => $gene_name ) or die "gene $gene_name not found\n";
    my $locus_id = $locus->locus_id;
    my $des = $locus->gene_description;
    
    print join ("\t", ($chr,"comm_anno","mRNA",$span_start,$span_end,".",$strand,".", "mRNA commanno_$locus_id; Note \"$gene_name\"; Alias \"$des\"; user_id \"$user_id\"; family_id \"$family_id\""))."\n";
    #workout if utr are present
    if ( $strand eq "+") {
      HSP: for my $hsp(@hsps){
            #all CDS
            if ( $trans_start <= $hsp->[2] && $trans_stop >= $hsp->[3] ) {
                print_exon_gff2($chr, "CDS", $hsp->[0], $hsp->[1], $strand, $locus_id);
            }
            #all 5'UTR
            elsif ( $trans_start > $hsp->[3] && $trans_stop > $hsp->[3] ) {
                print_exon_gff2($chr, "five_prime_UTR", $hsp->[0], $hsp->[1], $strand, $locus_id);
            }
            #all 3;UTR
            elsif ( $trans_start < $hsp->[2] && $trans_stop < $hsp->[2]) {
                print_exon_gff2($chr, "three_prime_UTR", $hsp->[0], $hsp->[1], $strand, $locus_id);
            }
            #exon is 5'UTR/CDS/3'UTR
            elsif ( $trans_start > $hsp->[2] && $trans_stop < $hsp->[3] ) {
				
                my $offset_left = $trans_start - $hsp->[2];
                my $offset_right = $hsp->[3] - $trans_stop;
				
                print_exon_gff2($chr, "five_prime_UTR", $hsp->[0], ($hsp->[0] + $offset_left - 1 ), $strand, $locus_id);
                print_exon_gff2($chr, "CDS", ( $hsp->[0] + $offset_left), ($hsp->[1] - $offset_right ), $strand, $locus_id);
                print_exon_gff2($chr, "three_prime_UTR",( $hsp->[1] - $offset_right + 1 ), $hsp->[1], $strand, $locus_id);
            }
            #part 5' UTR
            elsif ( $trans_start > $hsp->[2] && $trans_start <= $hsp->[3] && $trans_stop >= $hsp->[3] ) {
                my $offset = $trans_start - $hsp->[2];
                print_exon_gff2($chr, "five_prime_UTR", $hsp->[0], ( $hsp->[0] + $offset -1 ), $strand, $locus_id);
                print_exon_gff2($chr, "CDS", ( $hsp->[0] + $offset ), $hsp->[1], $strand, $locus_id);
            }
            #part 3' UTR
            elsif ( $trans_stop >= $hsp->[2] && $trans_stop < $hsp->[3] && $trans_start <= $hsp->[2] ) {
                my $offset = $trans_stop - $hsp->[2];
                print_exon_gff2($chr, "CDS", $hsp->[0], ( $hsp->[0] + $offset ), $strand, $locus_id);
                print_exon_gff2($chr, "three_prime_UTR", ( $hsp->[0] + $offset + 1 ), $hsp->[1], $strand, $locus_id);
            } else {
                die "something wrong: $gene_name\n".join ("\t", @$hsp)."\n";
            }	
        }
    } else {
        #handle the reverse stranded model here
      HSP: for my $hsp(@hsps){
            #all CDS
            if ( $trans_start <= $hsp->[2] && $trans_stop >= $hsp->[3] ) {
                print_exon_gff2($chr, "CDS", $hsp->[1], $hsp->[0], $strand, $locus_id);
            }
            #all 5'UTR
            elsif ( $trans_start > $hsp->[3] && $trans_stop > $hsp->[3] ) {
                print_exon_gff2($chr, "five_prime_UTR", $hsp->[1], $hsp->[0], $strand, $locus_id);
            }
            #all 3;UTR
            elsif ( $trans_start < $hsp->[2] && $trans_stop < $hsp->[2] ) {
                print_exon_gff2($chr, "three_prime_UTR", $hsp->[1], $hsp->[0], $strand, $locus_id);
            }
            #exon is 5'UTR/CDS/3'UTR
            elsif ( $trans_start > $hsp->[2] && $trans_stop < $hsp->[3] ) {
                my $offset_left = $trans_start - $hsp->[2];
                my $offset_right = $hsp->[3] - $trans_stop;
				
                print_exon_gff2($chr, "five_prime_UTR",($hsp->[0] - $offset_left + 1), $hsp->[0], $strand, $locus_id);
                print_exon_gff2($chr, "CDS", ( $hsp->[1] + $offset_right), ( $hsp->[0] - $offset_left), $strand, $locus_id);
                print_exon_gff2($chr, "three_prime_UTR",( $hsp->[1], $hsp->[1] + $offset_right - 1), $strand, $locus_id);
            }
            #part 5' UTR
            elsif ( $trans_start > $hsp->[2] && $trans_start <= $hsp->[3] && $trans_stop >= $hsp->[3] ) {
                my $offset = $trans_start - $hsp->[2];
                print_exon_gff2($chr, "five_prime_UTR", ( $hsp->[0] - $offset + 1), $hsp->[0], $strand, $locus_id);
                print_exon_gff2($chr, "CDS", $hsp->[1], ( $hsp->[0] - $offset ), $strand, $locus_id);
            }
            #part 3' UTR
            elsif ( $trans_stop >= $hsp->[2] && $trans_stop < $hsp->[3] && $trans_start <= $hsp->[2] ) {
                my $offset = $trans_stop - $hsp->[2];
                print_exon_gff2($chr, "CDS", ($hsp->[0] - $offset), $hsp->[0], $strand, $locus_id);
                print_exon_gff2($chr, "three_prime_UTR", $hsp->[1], ( $hsp->[0] - $offset - 1), $strand, $locus_id);
            } else {
                die "something wrong: $gene_name\n".join ("\t", @$hsp)."\n";
            }
        }
    }
}

sub print_exon_gff2 {
    my ($chr, $type, $start, $stop, $strand, $locus_id) = @_;
    print join ("\t", ($chr,"comm_anno",$type,$start,$stop,".",$strand,".", "mRNA commanno_$locus_id"))."\n";
}


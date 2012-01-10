#!/usr/bin/perl
# $Id: load_ca_db_from_excel.pl 542 2007-07-24 18:25:31Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# This scripts loads the functional annotation data submitted from a community annotator
# as an Excel spread sheet in the community annotation database (schema in the schema dir).
# The sheet has to be saved as a tab delimited file before import
# The colums must be as follows:
#  1:Locus Identifier 2:Gene Name 3:Alternate Gene Name 4:GenBank Genomic Acc 5:GenBank cDNA Acc
#  6:GenBank Protein Acc 7:Mutant 8:Comment
 
use strict;
use warnings;
use Getopt::Long;
use lib '../lib/';
use CA::CDBI;
use CA::loci;
use Bio::DB::GFF;
my ( $user_id, $pfam_id, $excel_tab_file );
my $result = GetOptions ("user_id=i" => \$user_id,
                         "pfam_id=i"   => \$pfam_id,
                         "excel_tab_file=s" => \$excel_tab_file,
                        );
unless ($user_id && $pfam_id && $excel_tab_file) {
    die "Usage: load_ca_db_from excel.pl --user_id --pfam_id --excel_tab_file\n";
}
#local GFF DB connection params
my $GFF_DB_ADAPTOR = 'dbi::mysql'; #Bio DB GFF
my $GFF_DB_NAME = 'rice';
my $GFF_DB_HOST = 'mysql-dmz';
my $GFF_DB_DSN = join( ':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST ) );
my $GFF_DB_USERNAME = 'access';
my $GFF_DB_PASSWORD ='access';

#need this db connection for base annotation data
my $gff_db =  Bio::DB::GFF->new( -adaptor => $GFF_DB_ADAPTOR,
                                 -dsn => $GFF_DB_DSN,
                                 -user => $GFF_DB_USERNAME,
                                 -pass => $GFF_DB_PASSWORD,
                               ) or die("cannot access Bio::DB::GFF database");

open(my $fh, '<', $excel_tab_file ) or die;
while (<$fh>) {
    chomp;
    my ($locus, $gene_name, $gene_description, $alt_gene_name, $genbank_genomic_acc, $genbank_cdna_acc, $genbank_protein_acc, $mutant_info, $comment ) = split(/\t/);
    my $original_annotation = get_original_annotation($locus);
    my $new_locus_row = CA::loci->insert({ locus_name => $locus,
                                           original_annotation =>  $original_annotation,
                                           user_id => $user_id,
                                           family_id => $pfam_id,
                                           gene_name => $gene_name || q{},
                                           gene_description => $gene_description || q{},
                                           alt_gene_name => $alt_gene_name || q{},
                                           genbank_genomic_acc => $genbank_genomic_acc || q{},
                                           genbank_cdna_acc => $genbank_cdna_acc || q{},
                                           genbank_protein_acc =>  $genbank_protein_acc || q{},
                                           mutant_info => $mutant_info || q{},
                                           comment => $comment || q{},
                                           has_structural_annotation => 0,
                                         }); 

}
close($fh);

sub get_original_annotation {
    my ($locus) = @_;
    #may have to change depending on your gff group name for the loci
    my ( $locus_feature_obj ) = $gff_db->get_feature_by_name('Gene' => $locus );
    my ( $notes ) = $locus_feature_obj->notes;
    return $notes;
}

#!/usr/bin/perl
# $Id: load_ca_db_from_excel.pl 542 2007-07-24 18:25:31Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# This scripts loads the functional annotation data submitted from a community annotator
# as an Excel spread sheet in the community annotation database (schema in the schema dir).
# The sheet has to be saved as a tab delimited file before import
# The columns must be as follows:
#  1:Locus Identifier 2:Gene Name 3:Gene Description 4:Alternate Gene Name 5:GenBank Genomic Acc 6:GenBank cDNA Acc
#  7:GenBank Protein Acc 8:Mutant 9:Comment

use strict;
use warnings;
use Getopt::Long;
use lib '../lib/';
use CA::CDBI;
use CA::loci;
use Bio::DB::SeqFeature::Store;

my ($user_id, $family_id, $family_name, $excel_tab_file, $is_public) = (0, 0, "", "", 0);
my $help;

GetOptions(
    "user_id=i"        => \$user_id,
    "family_id=i"      => \$family_id,
    "excel_tab_file=s" => \$excel_tab_file,
    "help"             => \$help
);

unless (($user_id && $family_id && $excel_tab_file) || !$help) {
    die
"Usage: load_ca_db_from excel.pl --user_id=<num> --family_id=<num> --excel_tab_file=<filename>\n";
}

#local GFF DB connection params
my $GFF_DB_ADAPTOR  = 'DBI::mysql';                                           #Bio DB GFF
my $GFF_DB_NAME     = 'medtr_gbrowse2';
my $GFF_DB_HOST     = 'mysql51-lan-dev';
my $GFF_DB_DSN      = join(':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST));
my $GFF_DB_USERNAME = 'access';
my $GFF_DB_PASSWORD = 'access';

#need this db connection for base annotation data
my $gff_db = Bio::DB::SeqFeature::Store->new(
    -adaptor => $GFF_DB_ADAPTOR,
    -dsn     => $GFF_DB_DSN,
    -user    => $GFF_DB_USERNAME,
    -pass    => $GFF_DB_PASSWORD,
) or die("cannot access Bio::DB::SeqFeature::Store database");

=comment
for( $gff_db->types ){
  print "Feature $_\n";
  my @feats =
    $gff_db->get_features_by_type( $_ );
  print "got ", scalar(@feats), " $_ features\n";
}
=cut

open(my $fh, '<', $excel_tab_file) or die;
while (<$fh>) {
    chomp;
    next if (/^Locus/);    #skip header line
    my (
        $gene_locus,     $gene_symbol,    $func_annotation,
        $alt_gene_name,  $gb_genomic_acc, $gb_cdna_acc,
        $gb_protein_acc, $mutant_info,    $reference_pub,  
        $comment
    ) = split(/\t/);
    
    my $original_annotation = get_original_annotation($locus);
    my $new_locus_obj = do('insert', 'loci', 
        {
            gene_locus                => $locus,
            orig_func_annotation      => $original_annotation,
            user_id                   => $user_id,
            family_id                 => $family_id,
            gene_name                 => $gene_name || q{},
            gene_description          => $gene_description || q{},
            alt_gene_name             => $alt_gene_name || q{},
            gb_genomic_acc            => $genbank_genomic_acc || q{},
            gb_cdna_acc               => $genbank_cdna_acc || q{},
            gb_protein_acc            => $genbank_protein_acc || q{},
            mutant_info               => $mutant_info || q{},
            comment                   => $comment || q{},
            has_structural_annotation => 0,
        }
    );
}
close($fh);

sub get_original_annotation {
    my ($locus) = @_;
    
    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $gff_db->get_features_by_name(-name => $locus, -type => 'gene');
    my ($notes)             = $locus_feature_obj->notes if(defined $locus_feature_obj);
    
    warn "[debug] $locus\t$notes\n";
    (defined $notes) ? return $notes : return "";
}

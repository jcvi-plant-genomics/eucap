#!/usr/local/bin/perl
# $Id: load_ca_db_from_model_gff.pl
# EuCAP - Eukaryotic Community Annotation Package
# This scripts loads the structural annotation data (in JSON format) derived from
# parsing the GMAP output and updates the loci table (has_structural_annotation flag)

use strict;
use warnings;
use Getopt::Long;

# Set the perl5lib path variable
BEGIN {
    unshift @INC, '../', './lib', './lib/5.16.1';
}
use EuCAP::DBHelper;

#use DBI;
use JSON;

##BioPerl modules
#use Bio::DB::SeqFeature::Store;
#use Bio::SeqFeature::Generic;
#
##Class::DBI (ORM) Classes
#use CA::DBHelper;
#
##local GFF DB connection params
#my $GFF_DB_ADAPTOR  = 'DBI::mysql';                                         #Bio DB SeqFeature Store
#my $GFF_DB_NAME     = 'medtr_gbrowse2';
#my $GFF_DB_HOST     = 'mysql51-lan-dev';
#my $GFF_DB_DSN      = join(':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST));
#my $GFF_DB_USERNAME = 'access';
#my $GFF_DB_PASSWORD = 'access';
#
##my $gff_dbh = get_database_handle($GFF_DB_ADAPTOR, $GFF_DB_DSN, $GFF_DB_USERNAME, $GFF_DB_PASSWORD) or die;

my ($user_id, $family_id, $model_gff_file) = (0, 0, "");
GetOptions("model_gff_file=s" => \$model_gff_file);

unless ($model_gff_file) {
    die "Usage: load_ca_db_from_model_gff.pl --model_gff_file=<filename>\n";
}

open(my $fh, '<', $model_gff_file) or die;
my (
    $seq_id,    $start,    $stop,       $strand,   $num_strand, $type,
    $gene_name, $locus_id, $locus_name, $gff_data, $temp
);
my ($ca_gene_models, $ca_model_ds, $ca_model_json, $loci_obj);
while (<$fh>) {
    chomp;
    if (/\s+mRNA\s+\d+/) {
        if ($locus_id and $gff_data ne "") {
            $loci_obj = selectrow(
                { table => 'loci', where => { locus_id => $locus_id, gene_symbol => $gene_name } });
            $locus_name = $loci_obj->gene_locus;
            $ca_model_json .= "]}";

            #( $ca_gene_models ) = get_annotation_db_features($locus_name, $gff_dbh);
            #( $ca_model_ds, $ca_model_json ) = generate_initial_ca_model_ds($ca_gene_models->[0]);
            print "$locus_name\t$gene_name\n";
            my $new_struct_annot_row = do(
                'insert',
                'structural_annot',
                {
                    locus_id => $locus_id,
                    user_id => $user_id,
                    model    => $ca_model_json
                }
            );
            my $locus_row = selectrow({ table => 'loci', primary_key => $locus_id });
            $locus_row->has_structural_annot(1);
            $locus_row->update;
            $gff_data = "";
        }
        ($seq_id, $start, $stop, $strand, $gene_name, $locus_id, $user_id) = $_ =~
/^(\S+)\s+\S+\s+mRNA\s+(\d+)\s+(\d+)\s+\.\s+(\S+)\s+\.\s+mRNA (\S+); Note ".*"; Alias "commanno_(\d+)"; user_id "(\d+)"/;
        if ($strand eq "-") {
            $temp       = $start;
            $start      = $stop;
            $stop       = $temp;
            $num_strand = -1;
        }
        else {
            $num_strand = 1;
        }
        $ca_model_json =
"{\"stop\":$stop,\"seq_id\":\"$seq_id\",\"strand\":$num_strand,\"type\":\"processed_transcript\",\"start\":$start,\"name\":\"$gene_name\",\"subfeatures\":[";
        $gff_data = "$_\n";
    }
    elsif (/mRNA $gene_name/) {
        ($seq_id, $type, $start, $stop, $strand) =
          $_ =~ /^(\S+)\s+\S+\s+(\S+)\s+(\d+)\s+(\d+)\s+\.\s+(\S+)\s+\.\s+mRNA $gene_name/;
        if ($strand eq "-") {
            $temp  = $start;
            $start = $stop;
            $stop  = $temp;
        }
        if ($ca_model_json =~ /"subfeatures":\[$/) {
            $ca_model_json .= "{\"stop\":$stop,\"type\":\"$type\",\"start\":$start}";
        }
        else {
            $ca_model_json .= ",{\"stop\":$stop,\"type\":\"$type\",\"start\":$start}";
        }
        $gff_data .= "$_\n";
    }
}
$loci_obj =
  selectrow({ table => 'loci', where => { locus_id => $locus_id, gene_symbol => $gene_name } });
$locus_name = $loci_obj->gene_locus;
$ca_model_json .= "]}";

#( $ca_gene_models ) = get_annotation_db_features($locus_name, $gff_dbh);
#( $ca_model_ds, $ca_model_json ) = generate_initial_ca_model_ds($ca_gene_models->[0]);
print "$locus_name\t$gene_name\n";
my $new_struct_annot_row = do(
    'insert',
    'structural_annot',
    {
        locus_id => $locus_id,
        user_id => $user_id,
        model    => $ca_model_json
    }
);
my $locus_row = selectrow({ table => 'loci', primary_key => $locus_id });
$locus_row->has_structural_annot(1);
$locus_row->update;
close($fh);

exit;

=comment
## Structural annotation subroutines ##
sub generate_initial_ca_model_ds {
    my ($ref_gene_model) = @_;
    my @subfeatures = $ref_gene_model->get_SeqFeatures();
    @subfeatures = sort { $ref_gene_model->strand == 1 ?
                            $a->start <=> $b->start : $b->start <=> $a->start } @subfeatures;
    my $comm_anno_ds = {};
    $comm_anno_ds->{subfeatures} = [];
    $comm_anno_ds->{type} = $ref_gene_model->primary_tag;
    $comm_anno_ds->{seq_id} = $ref_gene_model->seq_id;
    $comm_anno_ds->{start} = $ref_gene_model->start;
    $comm_anno_ds->{stop} = $ref_gene_model->stop;
    $comm_anno_ds->{strand} = $ref_gene_model->strand;
    for my $subfeature ( @subfeatures ) {
        my $subfeature_ds = {};
        $subfeature_ds->{type} = $subfeature->primary_tag;
        $subfeature_ds->{start} = $subfeature->start;
        $subfeature_ds->{stop} = $subfeature->stop;
        push(@{$comm_anno_ds->{subfeatures}}, $subfeature_ds);
    }
    my $json_handler = JSON->new;
    my $comm_anno_model_json =  $json_handler->encode($comm_anno_ds);
    return ( $comm_anno_ds, $comm_anno_model_json );

}

sub get_database_handle {
    my ( $adaptor, $dsn, $user, $password ) = @_;
    my $processed_transcript_aggregator = Bio::DB::GFF::Aggregator->new(-method => "processed_transcript",
                                                                        -main_method  => "mRNA",
                                                                        -sub_parts    => ["three_prime_UTR","CDS",  "five_prime_UTR"]
                                                                       );

    my $gff_db =  Bio::DB::GFF->new( -adaptor => $adaptor,
                                     -aggregator => [$processed_transcript_aggregator],
                                     -dsn => $dsn,
                                     -user => $user,
                                     -pass => $password,
                                   ) or die("cannot access Bio::DB::GFF database");
    return $gff_db;
}

sub get_annotation_db_features {
    my ($locus, $gff_dbh) = @_;
    my ( $locus_obj ) = $gff_dbh->get_feature_by_name('gene' => $locus );
    my ( $end5, $end3 ) = get_ends_from_feature( $locus_obj );
    my $seg = $gff_dbh->segment($locus_obj->refseq, $end5 => $end3 );
    my @gene_models = $seg->features('processed_transcript:comm_anno', -attributes => { 'gene' => $locus } );
    #will have to sort the gene models
    return (\@gene_models);
}

sub get_ends_from_feature {
    my ( $feature ) = @_;
    #my $end5 = $locus_obj->strand == 1 ? $locus_obj->start : $locus_obj->end;
    #my $end3 = $locus_obj->strand == 1 ? $locus_obj->end : $locus_obj->start;
    my $end5 = $feature->strand == 1 ? $feature->start : $feature->end;
    my $end3 = $feature->strand == 1 ? $feature->end : $feature->start;
    return ( $end5, $end3 );
}
=cut

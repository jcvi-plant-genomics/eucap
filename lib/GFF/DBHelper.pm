package AnnotDB::DBHelper;

use strict;

# Third-party modules
use Bio::DB::SeqFeature::Store;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(get_loci get_original_annotation get_annotation_db_features get_ends_from_feature);

my ($GFF_DB_ADAPTOR, $GFF_DB_DSN, $GFF_DB_USERNAME, $GFF_DB_PASSWORD) = getConfig();
my $gff_dbh = Bio::DB::SeqFeature::Store->new(
    -adaptor => $GFF_DB_ADAPTOR,
    -dsn     => $GFF_DB_DSN,
    -user    => $GFF_DB_USERNAME,
    -pass    => $GFF_DB_PASSWORD,
) or die("cannot access Bio::DB::SeqFeature::Store database");

sub getConfig {
    # Read the eucap.ini configuration file
    my %cfg = ();
    tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

    #local GFF DB connection params
    my $GFF_DB_ADAPTOR  = 'DBI::mysql';
    my $GFF_DB_HOST     = $cfg{'annotdb'}{'hostname'};
    my $GFF_DB_NAME     = $cfg{'annotdb'}{'database'};
    my $GFF_DB_USERNAME = $cfg{'annotdb'}{'username'};
    my $GFF_DB_PASSWORD = $cfg{'annotdb'}{'password'};
    my $GFF_DB_DSN      = join(':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST));

    return ($GFF_DB_ADAPTOR, $GFF_DB_DSN, $GFF_DB_USERNAME, $GFF_DB_PASSWORD);
}

sub get_loci {
    my ($arg_ref) = @_;

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    # EXECUTE THE QUERY
    my @locus_feats = $gff_dbh->get_features_by_name(
        -name  => "$arg_ref->{gene_locus}*",
        -types => 'gene'
    );

    # LOOP THROUGH RESULTS
    my @query_output = ();
    foreach my $locus_obj (@locus_feats) {
        my $id = $locus_obj->name;
        $id =~ s/\D+//gs;
        if ($arg_ref->{app} eq "autocmp") {
            push @query_output,
              {
                'id'              => $id,
                'locus'           => $locus_obj->name,
                'func_annotation' => $locus_obj->notes
              };
        }
        else {
            my $label = join " ", $locus_obj->name, $locus_obj->notes;
            push @query_output,
              {
                'id'    => $id,
                'value' => $locus_obj->name,
                'label' => $label,
              };
        }
    }
    @query_output = sort { $a->{id} <=> $b->{id} } @query_output if ($arg_ref->{app});
    @query_output =
      (scalar @query_output >= $arg_ref->{limit})
      ? @query_output[ 0 .. --$arg_ref->{limit} ]
      : @query_output;

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

sub get_original_annotation {
    my ($locus) = @_;

    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $gff_dbh->get_features_by_name(-name => $locus, -types => 'gene');
    my ($notes) = $locus_feature_obj->notes if (defined $locus_feature_obj);

    (defined $notes) ? return $notes : return "";
}

sub get_annotation_db_features {
    my ($arg_ref) = @_;

    my ($gff_locus_obj) = $gff_dbh->get_features_by_name(-name => $arg_ref->{locus}, -types => 'gene');
    my ($end5, $end3) = get_ends_from_feature($gff_locus_obj);
    my $segment = $gff_dbh->segment($gff_locus_obj->seq_id, $end5, $end3);
    my @gene_models = $segment->features(
        -name  => $arg_ref->{locus} . "*",
        -types => 'mRNA',
    );

    #will have to sort the gene models
    return ($gff_locus_obj, \@gene_models);
}

sub get_ends_from_feature {
    my ($gff_locus_obj) = @_;

    my ($end5, $end3) =
      $gff_locus_obj->strand == 1
      ? ($gff_locus_obj->start, $gff_locus_obj->end)
      : ($gff_locus_obj->end, $gff_locus_obj->start);

    #my $end3 = $locus_obj->strand == 1 ? $locus_obj->end : $locus_obj->start;

    return ($end5, $end3);
}

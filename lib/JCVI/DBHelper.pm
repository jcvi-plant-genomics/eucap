package JCVI::DBHelper;

use strict;
use Data::Dumper;

# Class::DBI ORM classes
use JCVI::DB::CDBI;
use JCVI::DB::ident;
#use JCVI::DB::ident_xref;
#use JCVI::DB::feat_link;
#use JCVI::DB::asm_feature;
#use JCVI::DB::phys_ev;

use constant MODULE => "JCVI::DB";

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA = qw(Exporter);
@EXPORT = qw(get_loci get_original_annotation get_annotation_db_features get_ends_from_feature);

sub get_loci {
    my ($arg_ref) = @_;
    my $Class = join "::", MODULE, "ident";
    
    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    # EXECUTE THE QUERY
    my $sth = $Class->sql_get_loci;
    $sth->execute($arg_ref->{gene_locus} . "%");
    my @locus_feats = $Class->sth_to_objects($sth);
    
    # LOOP THROUGH RESULTS
    my @query_output = ();
    foreach my $locus_obj (@locus_feats) {
        my $id = $locus_obj->com_name;
        $id =~ s/\D+//gs;
        if ($arg_ref->{app} eq "autocmp") {
            push @query_output,
              {
                'id'              => $id,
                'locus'           => $locus_obj->locus,
                'func_annotation' => $locus_obj->com_name
              };
        }
        else {
            my $label = join " ", $locus_obj->locus, $locus_obj->com_name;
            push @query_output,
              {
                'id'    => $id,
                'value' => $locus_obj->locus,
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
    my $Class = join "::", MODULE, "ident";
    
    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $Class->search(feat_name => $locus);
    my ($com_name) = $locus_feature_obj->com_name if (defined $locus_feature_obj);

    (defined $com_name) ? return $com_name : return "";    
}

sub get_annotation_db_features {
    
}

sub get_ends_from_feature {
    
}

1;
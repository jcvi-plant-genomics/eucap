package JCVI::DBHelper;

use strict;
use Data::Dumper;

# Class::DBI ORM classes
use JCVI::DB::CDBI;
use JCVI::DB::ident;
use JCVI::DB::asm_feature;
use JCVI::DB::ident_xref;
use JCVI::DB::clone_info;
#
#use JCVI::DB::feat_link;
#use JCVI::DB::phys_ev;

use constant MODULE => "JCVI::DB";

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA = qw(Exporter);
@EXPORT =
  qw(get_loci get_original_annotation get_genbank_accession get_annotation_db_features get_ends_from_feature);

sub get_loci {
    my ($arg_ref) = @_;
    my $Class = join "::", MODULE, "ident";

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    # EXECUTE THE QUERY
    my @locus_feats = $Class->search_get_loci($arg_ref->{gene_locus} . '%');

    # LOOP THROUGH RESULTS
    my @query_output = ();
    foreach my $locus_obj (@locus_feats) {
        my $id = $locus_obj->locus;
        $id =~ s/\D+//gs;
        if ($arg_ref->{app} eq "autocmp") {
            push @query_output,
              {
                'id'              => $id,
                'locus'           => $locus_obj->locus,
                'func_annotation' => $locus_obj->com_name,
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

    my ($locus_feature_obj) = $Class->retrieve('locus' => $locus);
    my ($com_name) = $locus_feature_obj->com_name if (defined $locus_feature_obj);

    (defined $com_name) ? return $com_name : return "";
}

sub get_genbank_accession {
    my ($locus) = @_;
    my $Class = join "::", MODULE, "ident_xref";

    my ($gb_protein_acc) = $Class->sql_get_gb_acc($locus)->select_val;
    (defined $gb_protein_acc) ? return $gb_protein_acc : return "";
}

sub get_annotation_db_features {
    my ($locus) = @_;
    my $Class = join "::", MODULE, "ident";

    my @locus_feats = $Class->search_get_loci($locus);
    my $locus_obj;
    foreach my $feat (@locus_feats) {
        $locus_obj = $feat;
    }

    my $Class = join "::", MODULE, "clone_info";
    my $seq_id = $Class->sql_get_clone_name($locus_obj)->select_val;

    my $locus_obj = _create_feature({
        'obj' => $locus_obj,
        'seq_id' => $seq_id,
        'feat_type' => 'gene',
        'desc' => $locus_obj->com_name,
    });

    my $Class = join "::", MODULE, "ident";

    my @gene_models = ();
    my @models      = $Class->search_get_models($locus);
    foreach my $model_obj (@models) {
        push @gene_models, _create_feature({
            'obj' => $model_obj,
            'seq_id' => $seq_id,
            'feat_type' => 'mRNA',
            'subfeats' => 1,
        });
    }

    return ($locus_obj, \@gene_models);
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

sub get_ends_from_db_obj {
    my ($obj) = @_;

    my $Class = join "::", MODULE, "asm_feature";
    my $feat_obj = $Class->retrieve('feat_name' => $obj->feat_name);

    my ($end5, $end3) = ($feat_obj->end5, $feat_obj->end3);

    return ($end5, $end3);
}

sub _create_feature {
    my ($arg_ref) = @_;

    my $subfeat_objs = [];
    if($arg_ref->{subfeats} == 1) {
        $subfeat_objs = _create_subfeatures({
            'obj' => $arg_ref->{obj},
            'seq_id' => $arg_ref->{seqid},
        })
    }

    my ($end5, $end3) = get_ends_from_db_obj($arg_ref->{obj});
    my ($start, $stop, $strand) = ($end5 > $end3) ? ($end3, $end5, -1) : ($end5, $end3, 1);

    my $feature = Bio::Graphics::Feature->new(
        -segments => $subfeat_objs,
        -start  => $start,
        -stop   => $stop,
        -type   => $arg_ref->{feat_type},
        -strand => $strand,
        -seq_id => $arg_ref->{seq_id},
        -name   => $arg_ref->{obj}->locus,
        -desc   => $arg_ref->{desc},
    );

    return $feature;
}

sub _create_subfeatures {
    my ($arg_ref) = @_;
    my $subfeat_objs = [];

    my $Class = join "::", MODULE, "asm_feature";
    my @exons = $Class->search_get_exons($arg_ref->{obj}->feat_name);
    for my $exon (@exons) {
        my ($start, $stop) =
            ($exon->end5 > $exon->end3)
          ? ($exon->end3, $exon->end5)
          : ($exon->end5, $exon->end3);
        my $subfeat_obj = Bio::Graphics::Feature->new(
            -seq_id => $arg_ref->{seq_id},
            -start  => $start,
            -stop   => $stop,
            -type   => 'exon',
            -strand => 1,
        );
        push(@$subfeat_objs, $subfeat_obj);

        my @CDSs = $Class->search_get_cds($exon->feat_name);
        for my $cds (@CDSs) {
            my ($start, $stop) =
                ($cds->end5 > $cds->end3)
              ? ($cds->end3, $cds->end5)
              : ($cds->end5, $cds->end3);
            my $subfeat_obj = Bio::Graphics::Feature->new(
                -seq_id => $arg_ref->{seq_id},
                -start  => $start,
                -stop   => $stop,
                -type   => 'CDS',
                -strand => 1,
            );
            push(@$subfeat_objs, $subfeat_obj);
        }
    }

    return $subfeat_objs;
}

1;

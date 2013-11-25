package AnnotDB::DBHelper;

use strict;
use Data::Dumper;

# Class::DBI ORM classes
use AnnotDB::DB::CDBI;
use AnnotDB::DB::ident;
use AnnotDB::DB::asm_feature;
use AnnotDB::DB::ident_xref;
use AnnotDB::DB::clone_info;
use AnnotDB::DB::feat_link;

#use AnnotDB::DB::phys_ev;

use constant MODULE => "AnnotDB::DB";

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
    my ($arg_ref) = @_;

    my $Class = join "::", MODULE, "ident";
    my $locus_feat_obj = $Class->retrieve('locus' => $arg_ref->{locus});

    $Class = join "::", MODULE, "clone_info";
    my $seq_id = $Class->sql_get_clone_name($arg_ref->{locus})->select_val;

    my $locus_obj = _create_feature(
        {
            'obj'       => $locus_feat_obj,
            'seq_id'    => $seq_id,
            'feat_type' => 'gene',
        }
    );

    $Class = join "::", MODULE, "ident";

    my @gene_models = ();
    my @model_feats = $Class->search_get_models($arg_ref->{locus});
    foreach my $model_feat_obj (@model_feats) {
        push @gene_models,
          _create_feature(
            {
                'obj'       => $model_feat_obj,
                'seq_id'    => $seq_id,
                'feat_type' => 'mRNA',
                'subfeats'  => 1,
            }
          );
    }

    return ($locus_obj, \@gene_models);
}

sub get_ends_from_feature {
    my ($locus_obj) = @_;

    my ($end5, $end3) =
      $locus_obj->strand == 1
      ? ($locus_obj->start, $locus_obj->end)
      : ($locus_obj->end, $locus_obj->start);

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

    my ($end5, $end3) = get_ends_from_db_obj($arg_ref->{obj});
    my ($start, $stop, $strand) = ($end5 > $end3) ? ($end3, $end5, -1) : ($end5, $end3, 1);

    my $feature = Bio::Graphics::Feature->new(
        -segments => ($arg_ref->{subfeats} == 1)
        ? _create_subfeatures({ 'obj' => $arg_ref->{obj}, 'seq_id' => $arg_ref->{seq_id} })
        : [],
        -start  => $start,
        -stop   => $stop,
        -type   => $arg_ref->{feat_type},
        -strand => $strand,
        -seq_id => $arg_ref->{seq_id},
        -name   => $arg_ref->{obj}->locus,
        -desc   => $arg_ref->{obj}->com_name,
    );

    return $feature;
}

sub _create_subfeatures {
    my ($arg_ref) = @_;
    my $subfeat_objs = [];

    my $Class = join "::", MODULE, "feat_link";
    my @exons = $Class->search_get_children($arg_ref->{obj}->feat_name);
    for my $exon (@exons) {
        $Class = join "::", MODULE, "asm_feature";
        my ($exon_obj) = $Class->retrieve('feat_name' => $exon->child_feat, 'feat_type' => 'exon');

        my ($start, $stop, $strand) =
            ($exon_obj->end5 > $exon_obj->end3)
          ? ($exon_obj->end3, $exon_obj->end5, -1)
          : ($exon_obj->end5, $exon_obj->end3, 1);

        my $exon_coord = my $utr_coord =
          Bio::Range->new(-start => $start, -end => $stop, -strand => $strand);

        $Class = join "::", MODULE, "feat_link";
        my @CDSs = $Class->search_get_children($exon->child_feat);
        for my $cds (@CDSs) {
            $Class = join "::", MODULE, "asm_feature";
            my ($cds_obj) = $Class->retrieve('feat_name' => $cds->child_feat, 'feat_type' => 'CDS');

            my ($start, $stop, $strand) =
                ($cds_obj->end5 > $cds_obj->end3)
              ? ($cds_obj->end3, $cds_obj->end5, -1)
              : ($cds_obj->end5, $cds_obj->end3, 1);

            my $subfeat_obj = Bio::Graphics::Feature->new(
                -seq_id => $arg_ref->{seq_id},
                -start  => $start,
                -stop   => $stop,
                -type   => 'CDS',
                -strand => 1,
            );
            push(@$subfeat_objs, $subfeat_obj);

            my $cds_coord = Bio::Range->new(-start => $start, -end => $stop, -strand => $strand);
            if ($exon_coord->equals($cds_coord)) {
                $utr_coord = undef;
            }
            else {
                ($exon_coord->start == $cds_coord->start)
                  ? $utr_coord->start($cds_coord->end + 1)
                  : $utr_coord->end($cds_coord->start - 1);
            }
        }

        if ($utr_coord) {
            my $subfeat_obj = Bio::Graphics::Feature->new(
                -seq_id => $arg_ref->{seq_id},
                -start  => $utr_coord->start,
                -stop   => $utr_coord->end,
                -type   => ($utr_coord->end == $exon_coord->end)
                ? ($strand == -1 ? 'five_prime_UTR' : 'three_prime_UTR')
                : ($strand == 1 ? 'five_prime_UTR' : 'three_prime_UTR'),
                -strand => 1,
            );
            push(@$subfeat_objs, $subfeat_obj);
        }
    }

    return $subfeat_objs;
}

1;

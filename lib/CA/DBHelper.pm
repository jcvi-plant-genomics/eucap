package CA::DBHelper;
use strict;
use Switch;

#Class::DBI (ORM) classes
use CA::CDBI;
use CA::family;
use CA::users;
use CA::registration_pending;
use CA::loci;
use CA::loci_edits;
use CA::mutant_class;
use CA::mutant_class_edits;
use CA::mutant_info;
use CA::mutant_info_edits;
use CA::alleles;
use CA::alleles_edits;
use CA::structural_annot;
use CA::structural_annot_edits;

use constant MODULE => 'CA';

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA = qw(Exporter);
@EXPORT =
  qw(do selectall_array selectall_iter selectall_id selectrow_hashref selectrow makerow_hashref max_id get_class_symbol get_info update_user_info);

my %primary_key = (
    'loci'             => 'locus_id',
    'mutant_info'      => 'mutant_id',
    'mutant_class'     => 'mutant_class_id',
    'alleles'          => 'allele_id',
    'structural_annot' => 'sa_id',
    'users'            => 'user_id',
    'family'           => 'family_id'
);

my %table_columns = (
    'loci' => [
        'gene_symbol',   'gene_locus',     'func_annotation', 'orig_func_annotation',
        'comment',       'gb_genomic_acc', 'gb_cdna_acc',     'gb_protein_acc',
        'reference_pub', 'mutant_id',      'mod_date',        'has_structural_annot'
    ],
    'mutant_info' => [
        'symbol',       'phenotype',       'reference_pub', 'reference_lab',
        'mapping_data', 'mutant_class_id', 'mod_date'
    ],
    'mutant_class' => [ 'symbol', 'symbol_name' ],
    'alleles' =>
      [ 'mutant_id', 'allele_name', 'alt_allele_names', 'reference_lab', 'altered_phenotype' ],
    'structural_annot' => ['model'],
    'users' => [ 'name', 'username', 'email', 'organization', 'url', 'photo_file_name' ],
    'family' => [ 'user_id', 'family_name', 'gene_class_symbol', 'description', 'source' ]
);

sub do {
    my ($action, $table, $arg_ref) = @_;

    my $caObj;
    my $Class = join '::', MODULE, $table;
    if ($action eq "insert") {
        $caObj = $Class->insert($arg_ref);
        $caObj->update;

        return $caObj;
    }
    elsif ($action eq "delete") {
        $caObj =
          (scalar keys %{ $arg_ref->{where} } > 0)
          ? selectrow({ table => $table, where       => $arg_ref->{where} })
          : selectrow({ table => $table, primary_key => $arg_ref->{primary_key} });
        $caObj->delete if (defined $caObj);
    }
    elsif ($action eq "update") {
        if ($table =~ /edits/) {
            $arg_ref->{obj}->set('edits' => JSON::to_json($arg_ref->{hashref}));
            $arg_ref->{obj}->update;

            return $arg_ref->{obj};
        }
        else {
            my @columns = @{ $table_columns{$table} };
            foreach my $column (@columns) {

                # update the $arg_ref->{obj} with values from $arg_ref->{hashref}
                $arg_ref->{obj}->set(
                    $column => ($arg_ref->{hashref}->{$column} eq "")
                    ? undef
                    : $arg_ref->{hashref}->{$column}
                );

                # remove the edit flag is current column is an edit
                $arg_ref->{hashref} = remove_edit_flag($arg_ref->{hashref}, $column)
                  if (defined $arg_ref->{hashref}->{"$column\_edit"});
            }
            $arg_ref->{obj}->update;

            return ($arg_ref->{obj}, $arg_ref->{hashref});
        }
    }
}

sub remove_edit_flag {
    my ($hash_ref, $column) = @_;
    delete $hash_ref->{"$column\_edit"};

    return $hash_ref;
}

sub selectall_array {
    my ($table, $where_ref, $attrs_ref) = @_;

    my $Class = join '::', MODULE, $table;
    my @caObjs = ();
    if (scalar keys %{$where_ref} > 0) {
        if (scalar keys %{$attrs_ref} > 0) {
            @caObjs = $Class->search_where($where_ref, $attrs_ref);
        }
        else {
            @caObjs = $Class->search_where(%{$where_ref});
        }
    }
    else {
        @caObjs = $Class->retrieve_all;
    }

    return @caObjs;
}

sub selectall_iter {
    my ($table, $where_ref, $attrs_ref) = @_;

    my $Class = join '::', MODULE, $table;
    my $caObjs = ();
    if (scalar keys %{$where_ref} > 0) {
        if (scalar keys %{$attrs_ref} > 0) {
            $caObjs = $Class->search_where($where_ref, $attrs_ref);
        }
        else {
            $caObjs = $Class->search_where(%{$where_ref});
        }
    }
    else {
        $caObjs = $Class->retrieve_all;
    }

    return $caObjs;
}

sub selectall_id {
    my ($table, $arg_ref) = @_;

    my $Class = join '::', MODULE, $table;
    my @orig_features = (defined $arg_ref) ? $Class->search_where(%{ $arg_ref }) : $Class->retrieve_all;

    $Class = join '::', MODULE, "$table\_edits";
    my @edited_features = (defined $arg_ref) ? $Class->search_where(%{ $arg_ref }) : $Class->retrieve_all;

    my %all_features = ();
    $all_features{ $_->get($primary_key{$table}) } = 1 foreach ((@orig_features, @edited_features));

    return %all_features;
}

sub selectrow_hashref {
    my ($arg_ref) = @_;

    #$arg_ref->{edits} = 1 if ($arg_ref->{table} =~ /edits/);
    $arg_ref->{obj} = selectrow($arg_ref);

    my $hashref = {};
    $hashref = makerow_hashref($arg_ref) if (defined $arg_ref->{obj});

    return $hashref;
}

sub selectrow {
    my ($arg_ref) = @_;

    my $Class = join "::", MODULE, $arg_ref->{table};

    my $caObj =
      (scalar keys %{ $arg_ref->{where} } > 0)
      ? $Class->retrieve(%{ $arg_ref->{where} })
      : $Class->retrieve($arg_ref->{primary_key});

    return $caObj;
}

sub selectmax_id {
    my ($arg_ref) = @_;

    my $Class = join "::", MODULE, $arg_ref->{table};
    my $max_id = $Class->maximum_value_of($arg_ref->{column});

    return $max_id;
}

sub makerow_hashref {
    my ($arg_ref) = @_;

    if (defined $arg_ref->{edits}) {
        my $hashref = {};

        my $edits = $arg_ref->{obj}->get('edits');
        $hashref = JSON::from_json($edits);

        return $hashref;
    }
    else {
        my %hash;
        my @columns = @{ $table_columns{ $arg_ref->{table} } };
        foreach my $column (@columns) {
            $hash{$column} =
              (not defined $arg_ref->{obj}->get($column)) ? "" : $arg_ref->{obj}->get($column);
        }

        return \%hash;
    }
}

sub max_id {
    my ($arg_ref) = @_;

    my $max_id =
      selectmax_id({ column => $primary_key{ $arg_ref->{table} }, table => $arg_ref->{table} });
    my $id = $max_id + 1;

    my $check = selectrow({ table => "$arg_ref->{table}_edits", primary_key => $id });
    until (not defined $check) {
        my $edits_max_id = selectmax_id(
            { column => $primary_key{ $arg_ref->{table} }, table => "$arg_ref->{table}_edits" });
        $id = $edits_max_id + 1
          if ($id <= $edits_max_id);

        $check = selectrow({ table => "$arg_ref->{table}_edits", primary_key => $id });
    }

    return $id;
}

sub get_class_symbol {

    # hack to inherit the mutant_class_symbol for
    # mutant_info entries with no symbol or symbol eq "-"
    my ($mutant_class_id) = @_;

    my $mutant_class_obj = selectrow({ table => 'mutant_class', primary_key => $mutant_class_id });
    my $mutant_symbol = $mutant_class_obj->symbol;

    return $mutant_symbol;
}

sub get_info {
    my ($arg_ref) = @_;
    my $hashref = selectrow_hashref({ table => $arg_ref->{table}, where => { $primary_key{ $arg_ref->{table} } => $arg_ref->{id} } });

    $arg_ref->{anno_ref}->{ $primary_key{ $arg_ref->{table} } } = $arg_ref->{id};
    $arg_ref->{anno_ref}->{ $arg_ref->{table} }->{ $arg_ref->{id} } = $hashref;

    $arg_ref->{session}->param('anno_ref', $arg_ref->{anno_ref});
    $arg_ref->{session}->flush;

    return $arg_ref->{anno_ref};
}

sub update_user_info {
    my ($user_id, $anno_ref) = @_;
    my $user_obj = selectrow({ table => 'users', where => { user_id => $user_id } });

    $user_obj->set(
        username        => $anno_ref->{users}->{$user_id}->{username},
        name            => $anno_ref->{users}->{$user_id}->{name},
        email           => $anno_ref->{users}->{$user_id}->{email},
        organization    => $anno_ref->{users}->{$user_id}->{organization},
        url             => $anno_ref->{users}->{$user_id}->{url},
        photo_file_name => $anno_ref->{users}->{$user_id}->{photo_file_name}
    );
    $user_obj->update;
}

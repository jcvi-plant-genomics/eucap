package EuCAP::DBHelper;

use strict;
use Data::Dumper;

# Third-party modules
use Data::Difference qw/data_diff/;

#Class::DBI (ORM) classes
use EuCAP::DB::CDBI;
use EuCAP::DB::users;
use EuCAP::DB::registration_pending;
# feature tables
use EuCAP::DB::family;
use EuCAP::DB::loci;
use EuCAP::DB::mutant_class;
use EuCAP::DB::mutant_info;
use EuCAP::DB::alleles;
use EuCAP::DB::structural_annot;
# feature edits tables
use EuCAP::DB::loci_edits;
use EuCAP::DB::mutant_class_edits;
use EuCAP::DB::mutant_info_edits;
use EuCAP::DB::alleles_edits;
use EuCAP::DB::structural_annot_edits;

use constant MODULE => 'EuCAP::DB';

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA = qw(Exporter);
@EXPORT =
  qw(do selectall_array selectall_iter selectall_id selectrow_hashref selectrow makerow_hashref max_id
  get_class_symbol update_session cmp_db_hashref get_feat_info count_features cgi_to_hashref timestamp);

# Table => primary key
my %primary_key = (
    'loci'             => 'locus_id',
    'mutant_info'      => 'mutant_id',
    'mutant_class'     => 'mutant_class_id',
    'alleles'          => 'allele_id',
    'structural_annot' => 'sa_id',
    'users'            => 'user_id',
    'family'           => 'family_id',
    'pub'              => 'pub_id'
);

# Table => [ column_list ]
my %table_columns = (
    'loci' => [
        'gene_symbol',   'gene_locus',     'func_annotation', 'orig_func_annotation',
        'comment',       'gb_genomic_acc', 'gb_cdna_acc',     'gb_protein_acc',
        'reference_pub', 'mutant_id',      'mod_date',        'has_structural_annot',
        'user_id'
    ],
    'mutant_info' => [
        'symbol',       'phenotype',       'reference_pub', 'reference_lab',
        'mapping_data', 'mutant_class_id', 'mod_date',      'user_id',
    ],
    'mutant_class' => [ 'symbol', 'symbol_name', 'user_id' ],
    'alleles'      => [
        'mutant_id',     'allele_name',       'alt_allele_names', 'genetic_bg',
        'reference_lab', 'altered_phenotype', 'user_id'
    ],
    'structural_annot'       => ['model'],
    'structural_annot_edits' => ['model'],
    'users' => [ 'name', 'username', 'salt', 'hash', 'email', 'organization', 'url' ],
    'family' => [ 'user_id', 'family_name', 'gene_class_symbol', 'description', 'source' ],
    'pub' => ['user_id', 'title', 'volume', 'issue', 'pyear', 'pages', 'ptype', 'authors', 'journal', 'pmid']
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
            $arg_ref->{obj}->set('edits' => JSON::to_json($arg_ref->{hashref})) if(defined $arg_ref->{hashref});

            foreach my $field('family_id', 'is_deleted') {
                $arg_ref->{obj}->set($field => $arg_ref->{$field}) if(defined $arg_ref->{$field});
            }

            $arg_ref->{obj}->update;

            return $arg_ref->{obj};
        }
        else {
            my @columns = @{ $table_columns{$table} };
            foreach my $column (@columns) {

                # update the $arg_ref->{obj} with values from $arg_ref->{hashref}
                $arg_ref->{obj}->set($column => $arg_ref->{hashref}->{$column})
                    if(defined $arg_ref->{hashref}->{$column});

                # remove the edit flag if current column is an edit
                $arg_ref->{hashref} = remove_edit_flag($arg_ref->{hashref}, $column)
                  if (defined $arg_ref->{hashref}->{$column . "_edit"});
            }
            $arg_ref->{obj}->update;

            return ($arg_ref->{obj}, $arg_ref->{hashref});
        }
    }
}

sub remove_edit_flag {
    my ($hash_ref, $column) = @_;
    delete $hash_ref->{$column . "_edit"};

    return $hash_ref;
}

sub selectall_array {
    my ($table, $where_ref, $attrs_ref) = @_;

    my $Class = join '::', MODULE, $table;
    my @caObjs = ();
    if (scalar keys %{$where_ref} > 0) {
        if (scalar keys %{$attrs_ref} > 0) {
            @caObjs = $Class->search_like(%{$where_ref}, $attrs_ref);
        }
        else {
            @caObjs = $Class->search_like(%{$where_ref});
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
            $caObjs = $Class->search_like(%{$where_ref}, $attrs_ref);
        }
        else {
            $caObjs = $Class->search_like(%{$where_ref});
        }
    }
    else {
        $caObjs = $Class->retrieve_all;
    }

    return $caObjs;
}

sub selectall_id {
    my ($arg_ref) = @_;

    my $Class = join '::', MODULE, $arg_ref->{table};
    my @orig_features =
      (defined $arg_ref->{where})
      ? $Class->search_like(%{ $arg_ref->{where} })
      : $Class->retrieve_all;

    $Class = join '::', MODULE, $arg_ref->{table} . "_edits";

    $arg_ref->{where}->{user_id} = $arg_ref->{user_id} if (defined $arg_ref->{user_id});
    $arg_ref->{where}->{is_deleted} = $arg_ref->{is_deleted} if (defined $arg_ref->{is_deleted});

    my @edited_features =
      (defined $arg_ref->{where})
      ? $Class->search_like(%{ $arg_ref->{where} })
      : $Class->retrieve_all;

    my %all_features = ();
    my $column =
      (defined $arg_ref->{column}) ? $arg_ref->{column} : $primary_key{ $arg_ref->{table} };

    $all_features{ $_->get($column) } = 1 foreach ((@orig_features, @edited_features));

    return %all_features;
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

sub selectrow_hashref {
    my ($arg_ref) = @_;

    #$arg_ref->{edits} = 1 if ($arg_ref->{table} =~ /edits/);
    $arg_ref->{obj} = selectrow($arg_ref);

    my $hashref = {};
    if (defined $arg_ref->{edits}) {
        my $is_deleted = 'N';
        ($hashref, $is_deleted) = makerow_hashref($arg_ref) if (defined $arg_ref->{obj});

        return ($hashref, $is_deleted);
    } else {
        $hashref = makerow_hashref($arg_ref) if (defined $arg_ref->{obj});

        return $hashref;
    }
}

sub makerow_hashref {
    my ($arg_ref) = @_;

    my $hashref = {};
    if (defined $arg_ref->{edits}) {
        my $edits = $arg_ref->{obj}->get('edits');
        $hashref  = JSON::from_json($edits);

        my $is_deleted = 'N';
        $is_deleted = $arg_ref->{obj}->get('is_deleted');

        return ($hashref, $is_deleted);
    }
    else {
        my @columns = @{ $table_columns{ $arg_ref->{table} } };
        foreach my $column (@columns) {
            $hashref->{$column} =
              (not defined $arg_ref->{obj}->get($column)) ? "" : $arg_ref->{obj}->get($column);
        }

        return $hashref;
    }
}

sub selectmax_id {
    my ($arg_ref) = @_;

    my $Class = join "::", MODULE, $arg_ref->{table};
    my $max_id = $Class->maximum_value_of($arg_ref->{column});

    return $max_id;
}

sub max_id {
    my ($arg_ref) = @_;

    my $max_id = selectmax_id(
        {
            column => $primary_key{ $arg_ref->{table} },
            table => $arg_ref->{table}
        }
    );
    my $id = $max_id + 1;

    my $edits_table = join "_", $arg_ref->{table}, "edits";
    while(1) {
        my $check = selectrow(
            {
                table => $edits_table,
                where => { $primary_key{ $arg_ref->{table} } => $id }
            }
        );
        last if (not defined $check);

        my $edits_max_id = selectmax_id(
            {
                column => $primary_key{ $arg_ref->{table} },
                table => $edits_table
            }
        );
        $id = $edits_max_id + 1 if ($id <= $edits_max_id);
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

sub update_session {
    my ($arg_ref) = @_;
    my $hashref = selectrow_hashref(
        {
            table => $arg_ref->{table},
            where => { $primary_key{ $arg_ref->{table} } => $arg_ref->{id} }
        }
    );

    $arg_ref->{anno_ref}->{ $primary_key{ $arg_ref->{table} } } = $arg_ref->{id};
    $arg_ref->{anno_ref}->{ $arg_ref->{table} }->{ $arg_ref->{id} } = $hashref;

    $arg_ref->{session}->param('anno_ref', $arg_ref->{anno_ref});
    $arg_ref->{session}->flush;

    return $arg_ref->{anno_ref};
}

#sub update_info {
#    my ($arg_ref) = @_;
#    my $id = $arg_ref->{ $primary_key{ $arg_ref->{table} } };
#
#    my $user_obj = selectrow({ table => $arg_ref->{table}, where => { $primary_key{ $arg_ref->{table} } => $id } });
#
#    foreach my $column(@{ $table_columns{ $arg_ref->{table} } }) {
#        $user_obj->set($column => $arg_ref->{anno_ref}->{$id}->{$column});
#    }
#
#    $user_obj->set(
#        username        => $anno_ref->{users}->{$user_id}->{username},
#        name            => $anno_ref->{users}->{$user_id}->{name},
#        email           => $anno_ref->{users}->{$user_id}->{email},
#        organization    => $anno_ref->{users}->{$user_id}->{organization},
#        url             => $anno_ref->{users}->{$user_id}->{url},
#        photo_file_name => $anno_ref->{users}->{$user_id}->{photo_file_name}
#    );
#    $user_obj->update;
#}

sub cmp_db_hashref {
    my ($arg_ref) = @_;

    my ($pick_edits, $e_flag) = (0, undef);
    my @differences = data_diff($arg_ref->{orig}, $arg_ref->{edits});

    foreach my $diff (@differences) {
        if ($diff->{path}[0] =~ /_edit/) {
            $e_flag = 1 if (defined $arg_ref->{is_admin});
            next;
        }
        if (defined $diff->{b} and $diff->{b} ne $diff->{a}) {
            $arg_ref->{edits}->{ $diff->{path}[0] . "_edit" } = 1;
            $pick_edits = 1;
        }
    }

    return ($arg_ref->{edits}, $pick_edits, $e_flag);
}

sub get_feat_info {
    my ($arg_ref) = @_;

    my $key = $primary_key{ $arg_ref->{table} };
    my $id = $arg_ref->{ $primary_key{ $arg_ref->{table} } };

    my $hashref = {};
    $hashref = selectrow_hashref(
        {
            table => $arg_ref->{table},
            where => { $key => $id }
        }
    );

    my $is_deleted    = 'N';
    my $edits_hashref = {};
    ($edits_hashref, $is_deleted) = selectrow_hashref(
        {
            table => $arg_ref->{table} . "_edits",
            where => {
                $key    => $id,
                user_id => $arg_ref->{user_id}
            },
            edits => 1
        }
    );

    my ($pick_edits, $deleted, $unapproved) = (undef, undef, undef);
    # if edits_hashref exists and has been deleted, pick it over the orig hashref
    # also check if its deleted, if so track the deletions
    # also check if orig hashref is empty, track all unapproved edits
    $unapproved = 1 if (scalar keys %{$edits_hashref} > 0 and defined $arg_ref->{extra_flags});
    if ($is_deleted eq 'Y') {
        $deleted = 1;
        $arg_ref->{anno_ref}->{ $arg_ref->{table} }->{$id} = $edits_hashref;
    }
    else {
        my $e_flag = undef;
        ($edits_hashref, $pick_edits, $e_flag) = cmp_db_hashref(
            {
                orig     => $hashref,
                edits    => $edits_hashref,
                is_admin => $arg_ref->{anno_ref}->{is_admin}
            }
        );

        ($edits_hashref->{is_edit}, $arg_ref->{anno_ref}->{ $arg_ref->{table} }->{$id}) =
          ($pick_edits) ? (1, $edits_hashref) : (undef, $hashref);
    }

    if(defined $arg_ref->{extra_flags}) {
        return ($arg_ref->{anno_ref}, $pick_edits, $unapproved, $deleted);
    } else {
        return ($arg_ref->{anno_ref}, $pick_edits);
    }
}

sub count_features {
    my ($arg_ref) = @_;

    # count the number of features both from
    # the original table & edits table
    my %all_features = selectall_id(
        {
            table      => $arg_ref->{table},
            where      => $arg_ref->{where},
            user_id    => $arg_ref->{user_id},
            is_deleted => 'N'
        }
    );

    return (scalar keys %all_features);
}

sub cgi_to_hashref {
    my ($arg_ref) = @_;

    ####### $cgi->parameter        => 'database_column_name' #######
    my %table_columns = (
        'cgi_loci' => {
            'gene_symbol'          => 'gene_symbol',
            'func_annotation'      => 'func_annotation',
            'gene_locus'           => 'gene_locus',
            'orig_func_annotation' => 'orig_func_annotation',
            'gb_genomic_acc'       => 'gb_genomic_acc',
            'gb_cdna_acc'          => 'gb_cdna_acc',
            'gb_protein_acc'       => 'gb_protein_acc',
            'reference_pub'        => 'reference_pub',
            'comment'              => 'comment',
            'has_structural_annot' => 'has_structural_annot',
        },
        'cgi_mutant_class' => {
            'mutant_class_id'     => 'mutant_class_id',
            'mutant_class_symbol' => 'mutant_class_symbol',
            'mutant_class_name'   => 'mutant_class_name',
        },
        'cgi_mutant_info' => {
            'mutant_class_id'      => 'mutant_class_id',
            'mutant_class_symbol'  => 'mutant_class_symbol',
            'mutant_class_name'    => 'mutant_class_name',
            'mutant_id'            => 'mutant_id',
            'mutant_symbol'        => 'mutant_symbol',
            'mutant_phenotype'     => 'mutant_phenotype',
            'mapping_data'         => 'mapping_data',
            'has_alleles'          => 'has_alleles',
            'mutant_reference_lab' => 'mutant_reference_lab',
            'mutant_reference_pub' => 'mutant_reference_pub',
        },
        'registration_pending' => {
            'username'       => 'username',
            'validation_key' => 'validation_key'
        },
        'users' => {
            'username'     => 'username',
            'password'     => 'password',
            'name'         => 'name',
            'email'        => 'email',
            'url'          => 'url',
            'organization' => 'organization'
        },
        'loci' => {
            'gene_symbol'          => 'gene_symbol',
            'gene_locus'           => 'gene_locus',
            'func_annotation'      => 'func_annotation',
            'orig_func_annotation' => 'orig_func_annotation',
            'comment'              => 'comment',
            'gb_genomic_acc'       => 'gb_genomic_acc',
            'gb_cdna_acc'          => 'gb_cdna_acc',
            'gb_protein_acc'       => 'gb_protein_acc',
            'reference_pub'        => 'reference_pub',
            'mutant_id'            => 'mutant_id',
            'has_structural_annot' => 'has_structural_annot'
        },
        'mutant_class' => {
            'mutant_class_symbol' => 'symbol',
            'mutant_class_name'   => 'symbol_name',
        },
        'mutant_info' => {
            'mutant_symbol'        => 'symbol',
            'mutant_phenotype'     => 'phenotype',
            'mutant_reference_pub' => 'reference_pub',
            'mutant_reference_lab' => 'reference_lab',
            'mapping_data'         => 'mapping_data',
            'genetic_bg'           => 'genetic_bg',
            'mutant_class_id'      => 'mutant_class_id',
            'has_alleles'          => 'has_alleles',
        },
        'alleles' => {
            'mutant_id'                        => "mutant_id",
            "allele_name_$arg_ref->{id}"       => "allele_name",
            "alt_allele_names_$arg_ref->{id}"  => "alt_allele_names",
            "genetic_bg_$arg_ref->{id}"        => "genetic_bg",
            "reference_lab_$arg_ref->{id}"     => "reference_lab",
            "altered_phenotype_$arg_ref->{id}" => "altered_phenotype"
        },
        'structural_annot' => { 'model_json' => 'model' }
    );

    my %hash;
    my %params = $arg_ref->{cgi}->Vars;
    foreach my $param (keys %params) {
        if (defined $table_columns{ $arg_ref->{table} }{$param}) {
            my $p = $params{$param};
            $p =~ s/^\s+|\s+$//g;

            $hash{ $table_columns{ $arg_ref->{table} }{$param} } = $p;
        }
    }

    return \%hash;
}

sub timestamp {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $timestamp = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $year + 1900,
      $mon + 1, $mday, $hour,
      $min, $sec;

    return $timestamp;
}

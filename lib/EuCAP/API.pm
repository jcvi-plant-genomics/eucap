package EuCAP::API;

use strict;
use EuCAP::DBHelper;
use EuCAP::Contact;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(get_mutant_info);

sub get_mutant_info {
    my ($arg_ref) = @_;

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    my @query_output = ();

    # if edits flag is enabled, search through original and edits table
    # and return a consolidated list (where the edits override the original
    # entries)
    if ($arg_ref->{edits}) {
        my @mutant_feats = ();
        my %all_mutant_class_ids =
          selectall_id({ table => 'mutant_class', user_id => $arg_ref->{user_id}, is_deleted => 'N' });
        foreach my $mutant_class_id (sort { $a <=> $b } keys %all_mutant_class_ids) {
            my $is_deleted = 'N';
            my $mutant_class_hashref = {};
            ($mutant_class_hashref, $is_deleted) = selectrow_hashref(
                {
                    table => 'mutant_class_edits',
                    where => { mutant_class_id => $mutant_class_id, user_id => $arg_ref->{user_id} },
                    edits => 1
                }
            );

            if (scalar keys %{$mutant_class_hashref} == 0) {
                $mutant_class_hashref =
                  selectrow_hashref({ table => 'mutant_class', where => { mutant_class_id => $mutant_class_id } });
            }
            $mutant_class_hashref->{mutant_class_id} = $mutant_class_id;

            if ($mutant_class_hashref->{symbol} =~ /^$arg_ref->{symbol}/i) {
                push @mutant_feats, $mutant_class_hashref;
            }
        }

        # LOOP THROUGH RESULTS
        foreach my $mutant_class_hashref (@mutant_feats) {
            my %all_mutant_ids = selectall_id(
                {
                    table   => 'mutant_info',
                    where   => { mutant_class_id => $mutant_class_hashref->{mutant_class_id} },
                    user_id => $arg_ref->{user_id},
                    is_deleted => 'N'
                }
            );

            foreach my $mutant_id (sort { $a <=> $b } keys %all_mutant_ids) {
                my $is_deleted = 'N';
                my $mutant_hashref = {};
                ($mutant_hashref, $is_deleted) = selectrow_hashref(
                    {
                        table => 'mutant_info_edits',
                        where => { mutant_id => $mutant_id, user_id => $arg_ref->{user_id} },
                        edits => 1
                    }
                );

                if (scalar keys %{$mutant_hashref} == 0 or $is_deleted eq 'Y') {
                    $mutant_hashref =
                      selectrow_hashref({ table => 'mutant_info', where => { mutant_id => $mutant_id } });
                }

                my %all_alleles = selectall_id(
                    {
                        table   => 'alleles',
                        where   => { mutant_id => $mutant_id },
                        user_id => $arg_ref->{user_id},
                        is_deleted => 'N'
                    }
                );

                push @query_output,
                  {
                    'id'    => $mutant_id,
                    'value' => ($mutant_hashref->{symbol} eq "-" or $mutant_hashref->{symbol} eq "")
                    ? $mutant_class_hashref->{symbol}
                    : $mutant_hashref->{symbol},
                    'phenotype'           => $mutant_hashref->{phenotype},
                    'mapping_data'        => $mutant_hashref->{mapping_data},
                    'reference_lab'       => $mutant_hashref->{reference_lab},
                    'reference_pub'       => $mutant_hashref->{reference_pub},
                    'has_alleles'         => scalar keys %all_alleles,
                    'mutant_class_id'     => $mutant_class_hashref->{mutant_class_id},
                    'mutant_class_symbol' => $mutant_class_hashref->{symbol},
                    'mutant_class_name'   => $mutant_class_hashref->{symbol_name}
                  };
            }
        }
    }
    else {

        #$arg_ref->{symbol} =~ s/[0-9]+$//gs;
        my @mutant_feats = selectall_array(
            'mutant_class',
            { symbol   => "$arg_ref->{symbol}%" },
            { order_by => 'mutant_class_id' }
        );

        # LOOP THROUGH RESULTS
        foreach my $mutant_class_obj (@mutant_feats) {
            my $mutant_objs =
              selectall_iter('mutant_info',
                { mutant_class_id => $mutant_class_obj->mutant_class_id });

            while (my $mutant_obj = $mutant_objs->next) {
                my @mutant_allele_objs =
                  selectall_array('alleles', { mutant_id => $mutant_obj->mutant_id });

                push @query_output,
                  {
                    'id'    => $mutant_obj->mutant_id,
                    'value' => ($mutant_obj->symbol eq "-" or $mutant_obj->symbol eq "")
                    ? $mutant_class_obj->symbol
                    : $mutant_obj->symbol,
                    'phenotype'     => $mutant_obj->phenotype,
                    'mapping_data'  => $mutant_obj->mapping_data,
                    'reference_lab' => $mutant_obj->reference_lab,
                    'reference_pub' => $mutant_obj->reference_pub,
                    'has_alleles'   => (scalar @mutant_allele_objs > 0) ? scalar @mutant_allele_objs
                    : 0,
                    'mutant_class_id'     => $mutant_class_obj->mutant_class_id,
                    'mutant_class_symbol' => $mutant_class_obj->symbol,
                    'mutant_class_name'   => $mutant_class_obj->symbol_name
                  };
            }
        }
    }

    @query_output =
      (scalar @query_output >= $arg_ref->{limit})
      ? @query_output[ 0 .. --$arg_ref->{limit} ]
      : @query_output;

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

1;

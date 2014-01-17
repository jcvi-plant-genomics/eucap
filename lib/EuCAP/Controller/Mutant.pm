package EuCAP::Controller::Mutant;

use strict;
use EuCAP::DBHelper;
use EuCAP::Controller::Mutant_class;

use Data::Dumper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(add_mutants annotate_mutant delete_mutant undelete_mutant);

sub add_mutants {
    my ($session, $cgi) = @_;
    my $mutant_list     = $cgi->param('mutants_list');
    my $mutant_class_id = $cgi->param('mutant_class_id');

    my $anno_ref = $session->param('anno_ref');

    my @new_mutants = split(/,/, $mutant_list);
    my $track = 0;
  MUTANT: foreach my $mutant_symbol (@new_mutants) {
        my $mutant_id = undef;
        $mutant_symbol =~ s/\s+//gs;

        my $mutant_class_symbol = $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol};
        next unless ($mutant_symbol =~ m/^$mutant_class_symbol/i);

        my $mutant_obj =
          selectrow({ table => 'mutant_info', where => { symbol => $mutant_symbol } });

        my $new_mutant_obj;
        if (defined $mutant_obj) {
            $mutant_id = $mutant_obj->mutant_id;
            my $mutant_edits_objs =
              selectall_iter('mutant_info_edits', { mutant_id => $mutant_id });
            while (my $mutant_edits_obj = $mutant_edits_objs->next()) {

                next
                  unless ($mutant_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($mutant_edits_obj->is_deleted eq 'Y') {

                    # If not 'admin' user, allow user to re-add the mutant
                    # else, delete the empty edits object, bring back
                    # the original entry and continue processing the
                    # input mutant list
                    $mutant_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
            }
            next MUTANT;
        }
        else {
            my $is_deleted        = 'N';
            my $mutant_edits_objs = selectall_iter('mutant_info_edits');
            while (my $mutant_edits_obj = $mutant_edits_objs->next()) {
                my $mutant_edits_hashref = {};

                ($mutant_edits_hashref, $is_deleted) = makerow_hashref(
                    {
                        obj   => $mutant_edits_obj,
                        table => 'mutant_info_edits',
                        edits => 1,
                    }
                );
                next unless ($mutant_edits_hashref->{symbol} eq $mutant_symbol);
                $mutant_id = $mutant_edits_obj->mutant_id;

                next
                  unless ($mutant_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($mutant_edits_obj->is_deleted eq 'Y') {
                    $mutant_id = $mutant_edits_obj->mutant_id;
                    $mutant_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
                else {
                    next MUTANT;
                }
            }
        }

        # If not 'admin', get max(mutant_id) after checking the 'mutants'
        # and 'mutants_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $mutant_id = max_id({ table => 'mutant_info' }) if (not defined $mutant_id);
        }
        else {    # else, insert new 'mutants' row, get $mutant_id and continue
            $new_mutant_obj =
              do('insert', 'mutant_info',
                { mutant_class_id => $mutant_class_id, user_id => $anno_ref->{user_id} });

            $mutant_id = $new_mutant_obj->mutant_id;
        }

      INSERT:
        $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id} = $mutant_class_id;
        $anno_ref->{mutant_info}->{$mutant_id}->{symbol}          = $mutant_symbol;
        $anno_ref->{mutant_info}->{$mutant_id}->{phenotype}       = q{};
        $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data}    = q{};
        $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab}   = q{};
        $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub}   = q{};
        $anno_ref->{mutant_info}->{$mutant_id}->{mod_date}        = timestamp();

        # delete the 'is_deleted' flag
        $anno_ref->{mutant_info}->{$mutant_id}->{is_deleted} = 'N';

        if (not defined $anno_ref->{is_admin}) {
            $new_mutant_obj = do(
                'insert',
                'mutant_info_edits',
                {
                    mutant_id       => $mutant_id,
                    mutant_class_id => $mutant_class_id,
                    user_id         => $anno_ref->{user_id},
                    edits           => JSON::to_json($anno_ref->{mutant_info}->{$mutant_id}),
                    is_deleted      => $anno_ref->{mutant_info}->{$mutant_id}->{is_deleted}
                }
            );
        }
        else {
            $new_mutant_obj->set(
                symbol        => $mutant_symbol,
                phenotype     => q{},
                mapping_data  => q{},
                reference_lab => q{},
                reference_pub => q{},
                mod_date      => $anno_ref->{mutant_info}->{$mutant_id}->{mod_date},
            );
        }

        $track++;
    }
    my $response = {};
    $response->{track} = $track;

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    #print $session->header(-type => 'text/plain');
    print $session->header(-type => 'application/json');

    #annotate($session, $cgi);
    #print $track, ' mutant', ($track >= 2 or $track == 0) ? 's' : '', ' added!';
    print JSON::to_json($response);
}

sub annotate_mutant {
    my ($arg_ref) = @_;

    my $anno_ref =
      (defined $arg_ref->{anno_ref})
      ? $arg_ref->{anno_ref}
      : $arg_ref->{session}->param('anno_ref');

    my $mutant_id;
    my $cgi_params;
    if (defined $arg_ref->{mutant_id}) {
        $mutant_id = $arg_ref->{mutant_id};
    }
    else {
        $mutant_id = $arg_ref->{cgi}->param('mutant_id');
    }

    if ($arg_ref->{save}) {
        $cgi_params =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'cgi_mutant_info', id => undef });

        my $response = (scalar keys %{ $arg_ref->{response} } > 0) ? $arg_ref->{response} : {};
        my $save_edits =
          (scalar keys %{ $arg_ref->{save_edits} } > 0) ? $arg_ref->{save_edits} : {};
        my $e_flag = undef;

        # Storing mutant_info - Check if req mutant_info fields have been passed:
        # if true: get mutant_id from param or max(mutant_id) + 1 from db or increment if it already exists in the edits table
        # else: undef the 'mutant_id' associated with current locus_id (if any) and remove mutant_edits from anno_ref
        my ($mutant_class_id) = undef;

#        $mutant_class_id = $cgi_params->{mutant_class_id};
#
#        if ($mutant_class_id) {
#            ($response, $save_edits, $anno_ref) = annotate_mutant_class(
#                {
#                    save            => 1,
#                    mutant_class_id => $mutant_class_id,
#                    cgi             => $arg_ref->{cgi},
#                    session         => $arg_ref->{session},
#                    anno_ref        => $anno_ref,
#                    result          => $response,
#                    save_edits      => $save_edits,
#                }
#            );
#        }

        # mutant already exists
        # check to see what has changed between the submission form and the database
        my $mutant_edits_hashref =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'mutant_info', id => undef });
        my $mutant_hashref = {};
        my @alleles        = ();

        my $mutant_symbol = $cgi_params->{mutant_symbol};

        my $is_deleted = 'N';

        # if mutant_id is not empty, just use the prexisting ID
        # otherwise, check and see if the mutant_symbol exists in the DB or not and get its ID
        if ($mutant_id eq "") {
            my %mutant_ids = selectall_id(
                {
                    table      => 'mutant_info',
                    where      => { mutant_class_id => $mutant_class_id },
                    user_id    => $anno_ref->{user_id},
                    is_deleted => 'N'
                }
            );

            foreach my $id (sort { $a <=> $b } keys %mutant_ids) {
                my $mutant_hashref =
                  selectrow_hashref({ table => 'mutant_info', where => { mutant_id => $id } });
                if (scalar keys %{$mutant_hashref} == 0) {
                    ($mutant_hashref, $is_deleted) = selectrow_hashref(
                        {
                            table => 'mutant_info_edits',
                            where => { mutant_id => $id, user_id => $anno_ref->{user_id} },
                            edits => 1
                        }
                    );
                }

                if ($mutant_hashref->{mutant_symbol} eq $mutant_symbol) {
                    $mutant_id = $id;
                    last;
                }
            }
        }

        if (!$mutant_id) {
            $mutant_id = max_id({ table => 'mutant_info' });
            $save_edits->{mutant_info} = 1;
        }
        else {
            ($mutant_hashref, $is_deleted) = selectrow_hashref(
                {
                    table => 'mutant_info_edits',
                    where => { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} },
                    edits => 1
                }
            );
            if (scalar keys %{$mutant_hashref} == 0) {
                $mutant_hashref = selectrow_hashref(
                    { table => 'mutant_info', where => { mutant_id => $mutant_id } });

                my ($mutant_symbol, $mutant_class_id) =
                  ($mutant_hashref->{symbol}, $mutant_hashref->{mutant_class_id});

                # hack currently in place to inherit mutant class symbol
                # when mutant_info symbol is missing
                $mutant_symbol = get_class_symbol($mutant_class_id)
                  if ( $mutant_hashref->{symbol} eq "-"
                    or $mutant_hashref->{symbol} eq "");

                $mutant_hashref->{symbol} = $mutant_symbol;
            }

            # count the number of alleles for the above mutant
            # both from the original & edits tables
            my %all_alleles = selectall_id(
                {
                    table      => 'alleles',
                    where      => { mutant_id => $mutant_id },
                    user_id    => $anno_ref->{user_id},
                    is_deleted => 'N'
                }
            );
            $mutant_hashref->{has_alleles} = scalar keys %all_alleles;

            $e_flag = undef;
            ($mutant_edits_hashref, $save_edits->{mutant_info}, $e_flag) = cmp_db_hashref(
                {
                    orig     => $mutant_hashref,
                    edits    => $mutant_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            $save_edits->{mutant_info} = 1
              if (defined $anno_ref->{is_admin} and defined $e_flag);
        }

        if ($arg_ref->{locus_id}) {
            $save_edits->{loci} = 1
              if ($anno_ref->{loci}->{ $arg_ref->{locus_id} }->{mutant_id} ne $mutant_id);

            $anno_ref->{loci}->{ $arg_ref->{locus_id} }->{mutant_id} = $mutant_id;
        }

        $anno_ref->{mutant_info}->{$mutant_id} =
          (defined $save_edits->{mutant_info})
          ? $mutant_edits_hashref
          : $mutant_hashref;

        $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id}
          if (not defined $mutant_class_id);

        if (defined $save_edits->{mutant_info} or defined $arg_ref->{update}) {
            $mutant_id = $anno_ref->{loci}->{ $arg_ref->{locus_id} }->{mutant_id}
              if ($arg_ref->{locus_id});
            $anno_ref->{mutant_info}->{$mutant_id}->{mod_date} = timestamp();

            if (defined $anno_ref->{is_admin}) {
                my $mutant_obj =
                  selectrow({ table => 'mutant_info', where => { mutant_id => $mutant_id } });

                if (not defined $mutant_obj) {
                    $mutant_obj =
                      do('insert', 'mutant_info',
                        { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} });
                }
                ($mutant_obj, $anno_ref->{mutant_info}->{$mutant_id}) = do(
                    'update',
                    'mutant_info',
                    {
                        hashref => $anno_ref->{mutant_info}->{$mutant_id},
                        obj     => $mutant_obj,
                    }
                );

                # delete the edits table entry (if exists)
                do('delete', 'mutant_info_edits', { where => { mutant_id => $mutant_id } });

                # no longer define mutant_id as an edit in session
                $anno_ref->{mutant_info}->{$mutant_id}->{is_edit} = undef;

                $response->{'mutant_info_edits'} = undef;
            }
            else {
                my $mutant_edits_obj = selectrow(
                    {
                        table => 'mutant_info_edits',
                        where => { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} }
                    }
                );

                if (defined $mutant_edits_obj) {
                    $mutant_edits_obj = do(
                        'update',
                        'mutant_info_edits',
                        {
                            hashref => $anno_ref->{mutant_info}->{$mutant_id},
                            obj     => $mutant_edits_obj,
                        }
                    );
                }
                else {
                    $mutant_edits_obj = do(
                        'insert',
                        'mutant_info_edits',
                        {
                            mutant_id => $mutant_id,
                            mutant_class_id => $mutant_class_id,
                            user_id    => $anno_ref->{user_id},
                            edits      => JSON::to_json($anno_ref->{mutant_info}->{$mutant_id}),
                            is_deleted => 'N'
                        }
                    );
                }
                $response->{'mutant_info_edits'} = 1;
            }

            $response->{'mutant_id'}       = $mutant_id;
            $response->{'mutant_mod_date'} = $anno_ref->{mutant_info}->{$mutant_id}->{mod_date};
            $response->{'has_alleles'}     = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};
            $response->{'updated_mutant'}  = 1;
        }
        $arg_ref->{session}->param('anno_ref', $anno_ref);
        $arg_ref->{session}->flush;

        # HTML header
        #print $arg_ref->{session}->header(-type => 'text/plain');
        #? print "Update success! Changes submitted for administrator approval."
        #: print 'No changes to update.';

        $response->{'updated'} = (
                 defined $save_edits->{mutant_info}
              or defined $save_edits->{mutant_class}
        ) ? 1 : undef;

        if ($arg_ref->{locus_id} or $arg_ref->{update}) {
            return ($response, $save_edits, $anno_ref);
        }
        else {
            print $arg_ref->{session}->header(-type => 'application/json');

            print JSON::to_json($response);
        }
    }
    else {
        my $annotate_mutant_loop = [];
        my @mutant_ids = split /,/, $mutant_id;
        foreach $mutant_id (sort { $a <=> $b } @mutant_ids) {
            my $mutant_row = {};

            $mutant_row->{mutant_id} = $mutant_id;
            $mutant_row->{user_id}   = $anno_ref->{user_id};

            my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

            $mutant_row = annotate_mutant_class(
                { mutant_class_id => $mutant_class_id, anno_ref => $anno_ref, row => $mutant_row });

            $mutant_row->{mutant_phenotype} = $anno_ref->{mutant_info}->{$mutant_id}->{phenotype};

            $anno_ref->{mutant_info}->{$mutant_id}->{symbol} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol}
              if ($anno_ref->{mutant_info}->{$mutant_id}->{symbol} eq "-");

            $mutant_row->{mutant_symbol} = $anno_ref->{mutant_info}->{$mutant_id}->{symbol};
            $mutant_row->{mapping_data}  = $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data};
            $mutant_row->{genetic_bg}    = $anno_ref->{mutant_info}->{$mutant_id}->{genetic_bg};
            $mutant_row->{mutant_reference_lab} =
              $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab};
            $mutant_row->{mutant_reference_pub} =
              $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub};
            $mutant_row->{mutant_mod_date} = $anno_ref->{mutant_info}->{$mutant_id}->{mod_date};
            $mutant_row->{has_alleles}     = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};

            if (defined $anno_ref->{is_admin}) {
                $mutant_row->{mutant_symbol_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{symbol_edit});
                $mutant_row->{mutant_class_symbol_edit} = 1
                  if (defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_edit});

#$mutant_row->{mutant_class_name_edit} = 1 if(defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name_edit});

                $mutant_row->{mutant_phenotype_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{phenotype_edit});
                $mutant_row->{mutant_reference_pub_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub_edit});
                $mutant_row->{mutant_reference_lab_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab_edit});
                $mutant_row->{mapping_data_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data_edit});
                $mutant_row->{genetic_bg_edit} = 1
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{genetic_bg_edit});
            }

            if (not defined $arg_ref->{row}) {
                $mutant_row->{is_mutant_edit} = 1;
            } else {
                $mutant_row->{locus_id} = $arg_ref->{row}->{locus_id};
            }

            push @$annotate_mutant_loop, $mutant_row;
        }

        if (defined $arg_ref->{row}) {
            $arg_ref->{row}->{annotate_mutant_loop} = $annotate_mutant_loop;
            return $arg_ref->{row};
        }
        else {
            my $body_tmpl = HTML::Template->new(filename => "./tmpl/annotate_mutant.tmpl");
            $body_tmpl->param(
                annotate_mutant_loop => $annotate_mutant_loop,
            );

            # HTML header
            print $arg_ref->{session}->header(-type => 'text/plain');

            print $body_tmpl->output;
        }
    }
}

sub delete_mutant {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_id       = $cgi->param('mutant_id');
    my $mutant_class_id = $cgi->param('mutant_class_id');

    # EXECUTE THE QUERY
    my $mutant_obj = selectrow({ table => 'mutant_info', where => { mutant_id => $mutant_id } });
    my $mutant_edits_obj = selectrow(
        {
            table => 'mutant_info_edits',
            where => { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} }
        }
    );

    my $response = {};
    $response->{deleted} = undef;

    my $is_deleted           = undef;
    my $mutant_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $mutant_edits_obj) {
            ($mutant_edits_hashref, $is_deleted) = makerow_hashref(
                { obj => $mutant_edits_obj, table => 'mutant_info_edits', edits => 1 });
            $is_deleted = 'Y';

            $mutant_edits_obj = do(
                'update',
                'mutant_info_edits',
                {
                    hashref    => $mutant_edits_hashref,
                    obj        => $mutant_edits_obj,
                    is_deleted => $is_deleted
                }
            );
        }
        else {    # otherwise, create a new edits_obj, with empty `edits` field
            $mutant_edits_hashref->{is_deleted} = 'Y';
            $mutant_edits_obj = do(
                'insert',
                'mutant_info_edits',
                {
                    mutant_id       => $mutant_id,
                    mutant_class_id => $mutant_class_id,
                    user_id         => $anno_ref->{user_id},
                    edits           => JSON::to_json($mutant_edits_hashref),
                    is_deleted      => $mutant_edits_hashref->{is_deleted}
                }
            );
        }
        $response->{deleted} = 1;
    }
    else {    # delete mutant_obj and mutant_edits_obj if 'admin'
        $mutant_edits_obj->delete if (defined $mutant_edits_obj);
        $mutant_obj->delete       if (defined $mutant_obj);

        delete $anno_ref->{mutant_info}->{$mutant_id};
        $response->{deleted} = 1;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    print JSON::to_json($response);
}

sub undelete_mutant {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_id = $cgi->param('mutant_id');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my ($mutant_hashref, $mutant_edits_hashref) = ({}, {});
    my $mutant_obj = selectrow({ table => 'mutant_info', where => { mutant_id => $mutant_id } });
    $mutant_hashref = makerow_hashref({ obj => $mutant_obj, table => 'mutant_info' })
      if (defined $mutant_obj);

    my $mutant_edits_obj = selectrow(
        {
            table => 'mutant_info_edits',
            where => { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} }
        }
    );

    my $is_deleted = 'N';
    ($mutant_edits_hashref, $is_deleted) =
      makerow_hashref({ obj => $mutant_edits_obj, table => 'mutant_info_edits', edits => 1 })
      if (defined $mutant_edits_obj);

    $is_deleted = 'N';

    $mutant_edits_obj = do(
        'update',
        'mutant_info_edits',
        {
            hashref    => $mutant_edits_hashref,
            obj        => $mutant_edits_obj,
            is_deleted => $is_deleted
        }
    );

    if (scalar keys %{$mutant_edits_hashref} == 0) {
        $mutant_edits_obj->delete;
        $anno_ref->{mutant_info}->{$mutant_id} = $mutant_hashref;
    }
    else {
        $anno_ref->{mutant_info}->{$mutant_id} = $mutant_edits_hashref;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print 'Reverted!';
}

1;

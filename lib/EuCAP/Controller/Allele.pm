package EuCAP::Controller::Allele;

use feature qw( state );
use strict;
use EuCAP::DBHelper;
use EuCAP::Controller::Mutant;

use Data::Dumper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(add_alleles annotate_alleles delete_allele undelete_allele);

sub add_alleles {
    my ($session, $cgi) = @_;
    my $allele_list = $cgi->param('alleles_list');
    my $mutant_id   = $cgi->param('mutant_id');

    my $anno_ref = $session->param('anno_ref');

    my @new_alleles = split(/,/, $allele_list);
    my $track = 0;
  ALLELE: foreach my $allele_name (@new_alleles) {
        my $allele_id = undef;
        $allele_name =~ s/\s+//gs;

        my $mutant_symbol = $anno_ref->{mutant_info}->{$mutant_id}->{symbol};
        ## Commented the following line out since the rule that allele name should
        ## have the mutant symbol in it (as a prefix), is not a valid assumption
        ## based on data available at NodMutDB
        #next unless ($allele_name =~ m/^$mutant_symbol\-\d+/i);

        my $allele_obj =
          selectrow({ table => 'alleles', where => { allele_name => $allele_name } });

        my $new_allele_obj;
        if (defined $allele_obj) {
            $allele_id = $allele_obj->allele_id;
            my $allele_edits_objs = selectall_iter('alleles_edits', { allele_id => $allele_id });
            while (my $allele_edits_obj = $allele_edits_objs->next()) {
                next
                  unless ($allele_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($allele_edits_obj->is_deleted eq 'Y') {

                    # If not 'admin' user, allow user to re-add the allele
                    # else, delete the empty edits object, bring back
                    # the original entry and continue processing the
                    # input allele list
                    $allele_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
            }
            next ALLELE;
        }
        else {
            my $is_deleted        = 'N';
            my $allele_edits_objs = selectall_iter('alleles_edits');
            while (my $allele_edits_obj = $allele_edits_objs->next()) {
                my $allele_edits_hashref = {};

                ($allele_edits_hashref, $is_deleted) = makerow_hashref(
                    { obj => $allele_edits_obj, table => 'alleles_edits', edits => 1 });

                next unless ($allele_edits_hashref->{allele_name} eq $allele_name);
                $allele_id = $allele_edits_obj->allele_id;

                next
                  unless ($allele_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($allele_edits_obj->is_deleted eq 'Y') {
                    $allele_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
                else {
                    next ALLELE;
                }
            }
        }

        # If not 'admin', get max(allele_id) after checking the 'alleles'
        # and 'alleles_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $allele_id = max_id({ table => 'alleles' }) if (not defined $allele_id);
        }
        else {    # else, insert new 'alleles' row, get $allele_id and continue
            $new_allele_obj = do('insert', 'alleles', { mutant_id => $mutant_id });

            $allele_id = $new_allele_obj->allele_id;
        }

      INSERT:
        $anno_ref->{alleles}->{$allele_id}->{mutant_id}         = $mutant_id;
        $anno_ref->{alleles}->{$allele_id}->{allele_name}       = $allele_name;
        $anno_ref->{alleles}->{$allele_id}->{alt_allele_names}  = q{};
        $anno_ref->{alleles}->{$allele_id}->{reference_lab}     = q{};
        $anno_ref->{alleles}->{$allele_id}->{altered_phenotype} = q{};

        if (not defined $anno_ref->{is_admin}) {
            $new_allele_obj = do(
                'insert',
                'alleles_edits',
                {
                    allele_id  => $allele_id,
                    mutant_id  => $mutant_id,
                    user_id    => $anno_ref->{user_id},
                    edits      => JSON::to_json($anno_ref->{alleles}->{$allele_id}),
                    is_deleted => 'N'
                }
            );
        }
        else {
            $new_allele_obj->set(
                allele_name       => $allele_name,
                alt_allele_names  => q{},
                reference_lab     => q{},
                altered_phenotype => q{},
            );
        }

        $track++;
    }

    my $response = {};
    if ($track >= 1) {
        my %all_alleles = selectall_id(
            {
                table      => 'alleles',
                where      => { mutant_id => $mutant_id },
                user_id    => $anno_ref->{user_id},
                is_deleted => 'N'
            }
        );
        $response->{has_alleles} = scalar keys %all_alleles;
#        my $save_edits = {};
#        ($response, $save_edits, $anno_ref) = annotate_mutant(
#            {
#                save       => 1,
#                update     => 1,
#                mutant_id  => $mutant_id,
#                cgi        => $cgi,
#                session    => $session,
#                anno_ref   => $anno_ref,
#                result     => $response,
#                save_edits => $save_edits,
#            }
#        );
    }

    $response->{track} = $track;

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    #print $session->header(-type => 'text/plain');
    print $session->header(-type => 'application/json');

    #annotate($session, $cgi);
    #print $track, ' allele', ($track >= 2 or $track == 0) ? 's' : '', ' added!';
    print JSON::to_json($response);
}

sub annotate_alleles {
    my ($session, $cgi, $save) = @_;
    my $body_tmpl      = HTML::Template->new(filename => "./tmpl/annotate_alleles.tmpl");
    my $anno_ref  = $session->param('anno_ref');
    my $mutant_id = $cgi->param('mutant_id');

    #save current value to db if save flag set
    if ($save) {
        my $save_edits = {};
        my $response     = {};
        my $e_flag     = undef;

        my $is_deleted = 'N';
        for my $allele_id (keys %{ $anno_ref->{alleles} }) {
            my $allele_hashref = {};

            ($allele_hashref, $is_deleted) = selectrow_hashref(
                {
                    table => 'alleles_edits',
                    where => { allele_id => $allele_id, user_id => $anno_ref->{user_id} },
                    edits => 1
                }
            );

            if (scalar keys %{$allele_hashref} == 0) {
                $allele_hashref =
                  selectrow_hashref({ table => 'alleles', where => { allele_id => $allele_id } });
            }

            my $allele_edits_hashref =
              cgi_to_hashref({ cgi => $cgi, table => 'alleles', id => $allele_id });

            ($allele_edits_hashref, $save_edits->{alleles}, $e_flag) = cmp_db_hashref(
                {
                    orig     => $allele_hashref,
                    edits    => $allele_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            $save_edits->{alleles} = 1
              if (defined $anno_ref->{is_admin} and defined $e_flag);

            $anno_ref->{mutant_info}->{$mutant_id}->{allele_id} = $allele_id;
            $anno_ref->{alleles}->{$allele_id} =
              ($save_edits->{alleles})
              ? $allele_edits_hashref
              : $allele_hashref;

            #save current value to db if save flag set
            if ($save_edits->{alleles}) {
                if (defined $anno_ref->{is_admin}) {
                    my $allele_obj =
                      selectrow({ table => 'alleles', where => { allele_id => $allele_id } });

                    if (not defined $allele_obj) {
                        $allele_obj = do(
                            'insert',
                            'alleles',
                            {
                                allele_id => $allele_id,
                                mutant_id => $mutant_id,
                                edits     => JSON::to_json($anno_ref->{alleles}->{$allele_id})
                            }
                        );
                    }
                    ($allele_obj, $anno_ref->{alleles}->{$allele_id}) = do(
                        'update',
                        'alleles',
                        {
                            hashref => $anno_ref->{alleles}->{$allele_id},
                            obj     => $allele_obj,
                        }
                    );

                    do('delete', 'alleles_edits', { where => { allele_id => $allele_id } });

                    $anno_ref->{alleles}->{$allele_id}->{is_edit} = undef;

                    $response->{'allele_edits'} = undef;
                }
                else {
                    my $allele_edits_obj = selectrow(
                        {
                            table => 'alleles_edits',
                            where => { allele_id => $allele_id, user_id => $anno_ref->{user_id} }
                        }
                    );

                    if (defined $allele_edits_obj) {
                        ($allele_edits_obj) = do(
                            'update',
                            'alleles_edits',
                            {
                                hashref => $anno_ref->{alleles}->{$allele_id},
                                obj     => $allele_edits_obj,
                            }
                        );
                    }
                    else {
                        $allele_edits_obj = do(
                            'insert',
                            'alleles_edits',
                            {
                                allele_id => $allele_id,
                                mutant_id => $mutant_id,
                                user_id   => $anno_ref->{user_id},
                                edits     => JSON::to_json($anno_ref->{alleles}->{$allele_id})
                            }
                        );
                    }
                    $response->{'allele_edits'} = 1;
                }
            }
        }

        if (defined $save_edits->{alleles}) {
            my %all_alleles = selectall_id(
                {
                    table      => 'alleles',
                    where      => { mutant_id => $mutant_id },
                    user_id    => $anno_ref->{user_id},
                    is_deleted => 'N'
                }
            );
            $response->{has_alleles} = scalar keys %all_alleles;
#            ($response, $save_edits, $anno_ref) = annotate_mutant(
#                {
#                    save       => 1,
#                    update     => 1,
#                    mutant_id  => $mutant_id,
#                    cgi        => $cgi,
#                    session    => $session,
#                    anno_ref   => $anno_ref,
#                    result     => $response,
#                    save_edits => $save_edits,
#                }
#            );
        }

        $session->param('anno_ref', $anno_ref);
        $session->flush;

        # HTML header
        print $session->header(-type => 'application/json');

        ($response->{'updated'}) = (defined $save_edits->{alleles}) ? 1 : undef;

        print JSON::to_json($response);
    }
    else {
        my $is_deleted     = 'N';
        my $mutant_hashref = {};

        ($mutant_hashref, $is_deleted) = selectrow_hashref(
            {
                table => 'mutant_info_edits',
                where => { mutant_id => $mutant_id, user_id => $anno_ref->{user_id} },
                edits => 1
            }
        );
        if (scalar keys %{$mutant_hashref} == 0) {
            $mutant_hashref =
              selectrow_hashref({ table => 'mutant_info', where => { mutant_id => $mutant_id } });
        }

        my $mutant_symbol   = $mutant_hashref->{symbol};
        my $mutant_class_id = $mutant_hashref->{mutant_class_id};
        $mutant_symbol = get_class_symbol($mutant_class_id)
          if ($mutant_hashref->{symbol} eq "-" or $mutant_hashref->{symbol} eq "");
        my $title = 'Annotate ' . $mutant_symbol . ' Alleles';

        my %all_alleles = selectall_id(
            {
                table   => 'alleles',
                where   => { mutant_id => $mutant_id },
                user_id => $anno_ref->{user_id},
            }
        );

        my %deleted_alleles    = ();
        my %unapproved_alleles = ();
        foreach my $allele_id (sort { $a <=> $b } keys %all_alleles) {
            my %pick_edits = ();

            $is_deleted = 'N';
            my $allele_edits_hashref = {};

            ($allele_edits_hashref, $is_deleted) = selectrow_hashref(
                {
                    table => 'alleles_edits',
                    where => { allele_id => $allele_id, user_id => $anno_ref->{user_id} },
                    edits => 1
                }
            );

            my $allele_hashref = {};
            $allele_hashref =
              selectrow_hashref({ table => 'alleles', where => { allele_id => $allele_id } });

            $unapproved_alleles{$allele_id} = 1 if (scalar keys %{$allele_hashref} == 0);
            if ($is_deleted eq 'Y') {
                $deleted_alleles{$allele_id} = 1;
                $anno_ref->{alleles}->{$allele_id} =
                  (scalar keys %{$allele_edits_hashref} > 1)
                  ? $allele_edits_hashref
                  : $allele_hashref;
                next;
            }

            #$allele_hashref->{is_edit} = undef;

            my $e_flag = undef;
            ($allele_edits_hashref, $pick_edits{alleles}, $e_flag) = cmp_db_hashref(
                {
                    orig     => $allele_hashref,
                    edits    => $allele_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            if ($pick_edits{alleles}) {
                $allele_edits_hashref->{is_edit} = 1;
                $anno_ref->{alleles}->{$allele_id} = $allele_edits_hashref;
            }
            else {
                $allele_hashref->{is_edit} = undef;
                $anno_ref->{alleles}->{$allele_id} = $allele_hashref;
            }
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        #now output the session
        my $i                    = 0;
        my $alleles_loop         = [];
        my $deleted_alleles_loop = [];
        my @allele_ids           = sort { $a <=> $b } keys %all_alleles;
        for my $allele_id (@allele_ids) {
            state $i;
            next if ($anno_ref->{alleles}->{$allele_id}->{mutant_id} != $mutant_id);

            my $row = {};

            $row->{allele_id}         = $allele_id;
            $row->{allele_name}       = $anno_ref->{alleles}->{$allele_id}->{allele_name};
            $row->{alt_allele_names}  = $anno_ref->{alleles}->{$allele_id}->{alt_allele_names};
            $row->{reference_lab}     = $anno_ref->{alleles}->{$allele_id}->{reference_lab};
            $row->{genetic_bg}        = $anno_ref->{alleles}->{$allele_id}->{genetic_bg};
            $row->{altered_phenotype} = $anno_ref->{alleles}->{$allele_id}->{altered_phenotype};

            #$row->{tableRowClass}     = ($i++ % 2 == 0) ? "tableRowEven" : "tableRowOdd";
            $row->{tableRowClass} = "tableRowOdd";

            $row->{unapproved} = 1 if (defined $unapproved_alleles{$allele_id});

            if (defined $anno_ref->{is_admin}) {
                my $allele_edits_obj =
                  selectrow({ table => 'alleles_edits', where => { allele_id => $allele_id } });
                $row->{tableRowClass} = "tableRowEdit" if (defined $allele_edits_obj);
            }

            if (defined $deleted_alleles{$allele_id}) {
                push @$deleted_alleles_loop, $row;
            }
            else {
                push @$alleles_loop, $row;
            }
        }
        $body_tmpl->param(
            mutant_id            => $mutant_id,
            symbol               => $mutant_symbol,
            alleles_loop         => $alleles_loop,
            deleted_alleles_loop => $deleted_alleles_loop
        );
        print $session->header(-type => 'text/plain');

        print $body_tmpl->output;
    }
}

sub delete_allele {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_id = $cgi->param('mutant_id');
    my $allele_id = $cgi->param('allele_id');

    # EXECUTE THE QUERY
    my $allele_obj = selectrow({ table => 'alleles', where => { allele_id => $allele_id } });
    my $allele_edits_obj = selectrow(
        {
            table => 'alleles_edits',
            where => { allele_id => $allele_id, user_id => $anno_ref->{user_id} }
        }
    );

    my $response = {};
    $response->{deleted} = undef;

    my $is_deleted           = undef;
    my $allele_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $allele_edits_obj) {
            ($allele_edits_hashref, $is_deleted) =
              makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits', edits => 1 });
            $is_deleted = 'Y';

            $allele_edits_obj = do(
                'update',
                'alleles_edits',
                {
                    obj        => $allele_edits_obj,
                    hashref    => $allele_edits_hashref,
                    is_deleted => $is_deleted
                }
            );
        }
        else {    # else delete the edits object (since it is unapproved)
            $is_deleted       = 'Y';
            $allele_edits_obj = do(
                'insert',
                'alleles_edits',
                {
                    allele_id  => $allele_id,
                    mutant_id  => $mutant_id,
                    user_id    => $anno_ref->{user_id},
                    edits      => JSON::to_json($allele_edits_hashref),
                    is_deleted => $is_deleted
                }
            );
        }
        $response->{deleted} = 1;
    }
    else {    # delete allele_obj if 'admin'
        $allele_edits_obj->delete if (defined $allele_edits_obj);
        $allele_obj->delete       if (defined $allele_obj);
        $response->{deleted} = 1;
    }

    delete $anno_ref->{alleles}->{$allele_id};
    $session->param('anno_ref', $anno_ref);
    $session->flush;

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    print JSON::to_json($response);
}

sub undelete_allele {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $allele_id = $cgi->param('allele_id');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my $allele_obj = selectrow({ table => 'alleles', where => { allele_id => $allele_id } });

    my $allele_hashref = {};
    $allele_hashref = makerow_hashref({ obj => $allele_obj, table => 'alleles' })
      if (defined $allele_obj);

    my $allele_edits_obj = selectrow(
        {
            table => 'alleles_edits',
            where => { allele_id => $allele_id, user_id => $anno_ref->{user_id} }
        }
    );

    my $is_deleted           = 'N';
    my $allele_edits_hashref = {};
    ($allele_edits_hashref, $is_deleted) =
      makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits', edits => 1 })
      if (defined $allele_edits_obj);

    $is_deleted = 'N';

    $allele_edits_obj = do(
        'update',
        'alleles_edits',
        {
            hashref    => $allele_edits_hashref,
            obj        => $allele_edits_obj,
            is_deleted => $is_deleted
        }
    );

    if (scalar keys %{$allele_edits_hashref} == 0) {
        $allele_edits_obj->delete;
        $anno_ref->{alleles}->{$allele_id} = $allele_hashref;
    }
    else {
        $anno_ref->{alleles}->{$allele_id} = $allele_edits_hashref;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print 'Reverted!';
}

1;

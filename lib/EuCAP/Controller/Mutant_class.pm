package EuCAP::Controller::Mutant_class;

use strict;
use EuCAP::DBHelper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(add_mutant_class annotate_mutant_class delete_mutant_class undelete_mutant_class);

sub add_mutant_class {
    my ($session, $cgi, $save) = @_;

    my $anno_ref = $session->param('anno_ref');
    my $user_id  = $anno_ref->{user_id};

    if ($save) {
        my $mutant_class_symbol = $cgi->param('mutant_class_symbol');
        my $mutant_class_name   = $cgi->param('mutant_class_name');

        $mutant_class_symbol =~ s/\s+//gs;
        $mutant_class_name   =~ s/^\s+|\s+$//g;

        my $track = 0;
        my $mutant_class_obj =
          selectrow({ table => 'mutant_class', where => { symbol => $mutant_class_symbol } });

        my $mutant_class_id = undef;
        my $new_mutant_obj;
        if (defined $mutant_class_obj) {
            $mutant_class_id = $mutant_class_obj->mutant_class_id;
            my $mutant_class_edits_objs =
              selectall_iter('mutant_class_edits', { mutant_class_id => $mutant_class_id });
            while (my $mutant_class_edits_obj = $mutant_class_edits_objs->next()) {
                next
                  unless ($mutant_class_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($mutant_class_edits_obj->is_deleted eq 'Y') {

                    # If not 'admin' user, allow user to re-add the mutant
                    # else, delete the empty edits object, bring back
                    # the original entry and continue processing the
                    # input mutant list
                    $mutant_class_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
            }
            goto TRACK;
        }
        else {
            my $is_deleted              = 'N';
            my $mutant_class_edits_objs = selectall_iter('mutant_class_edits');
            while (my $mutant_class_edits_obj = $mutant_class_edits_objs->next()) {
                my $mutant_class_edits_hashref = {};

                ($mutant_class_edits_hashref, $is_deleted) = makerow_hashref(
                    {
                        obj   => $mutant_class_edits_obj,
                        table => 'mutant_class_edits',
                        edits => 1,
                    }
                );
                next unless ($mutant_class_edits_hashref->{symbol} eq $mutant_class_symbol);
                $mutant_class_id = $mutant_class_edits_obj->mutant_class_id;

                next
                  unless ($mutant_class_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($mutant_class_edits_obj->is_deleted eq 'Y') {
                    $mutant_class_id = $mutant_class_edits_obj->mutant_class_id;
                    $mutant_class_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
                else {
                    goto TRACK;
                }
            }
        }

        # If not 'admin', get max(mutant_class_id) after checking the 'mutants'
        # and 'mutants_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $mutant_class_id = max_id({ table => 'mutant_class' })
              if (not defined $mutant_class_id);
        }
        else {    # else, insert new 'mutants' row, get $mutant_class_id and continue
            $new_mutant_obj =
              do('insert', 'mutant_class',
                { mutant_class_id => $mutant_class_id, user_id => $anno_ref->{user_id} });

            $mutant_class_id = $new_mutant_obj->mutant_class_id;
        }

      INSERT:
        $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol}      = $mutant_class_symbol;
        $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name} = $mutant_class_name;

        $anno_ref->{mutant_class}->{$mutant_class_id}->{is_deleted} = 'N';

        if (not defined $anno_ref->{is_admin}) {
            $new_mutant_obj = do(
                'insert',
                'mutant_class_edits',
                {
                    mutant_class_id => $mutant_class_id,
                    user_id         => $anno_ref->{user_id},
                    edits           => JSON::to_json($anno_ref->{mutant_class}->{$mutant_class_id}),
                    is_deleted      => $anno_ref->{mutant_class}->{$mutant_class_id}->{is_deleted}
                }
            );
        }
        else {
            $new_mutant_obj->set(
                user_id     => $anno_ref->{user_id},
                symbol      => $mutant_class_symbol,
                symbol_name => $mutant_class_name,
            );
        }
        $track++;

      TRACK:
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        print $session->header(-type => 'text/plain');

        #annotate($session, $cgi);
        print $track, ' mutant class', ($track == 0) ? 'es' : '', ' added!';
    }
    else {
        my $body_tmpl = HTML::Template->new(filename => "./tmpl/annotate_mutant_class.tmpl");

        $body_tmpl->param('user_id' => $user_id);

        print $session->header;
        print $body_tmpl->output;
    }
}

sub annotate_mutant_class {
    my ($arg_ref) = @_;

    #mutant_class info should already be in the session.
    my $anno_ref =
      (defined $arg_ref->{anno_ref})
      ? $arg_ref->{anno_ref}
      : $arg_ref->{session}->param('anno_ref');

    my $cgi_params;
    my $mutant_class_id;
    if (defined $arg_ref->{mutant_class_id}) {
        $mutant_class_id = $arg_ref->{mutant_class_id};
    }
    else {
        $mutant_class_id = $arg_ref->{cgi}->param('mutant_class_id');
    }

    if ($arg_ref->{save}) {
        $cgi_params =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'cgi_mutant_class', id => undef });

        my $response = (scalar keys %{ $arg_ref->{response} } > 0) ? $arg_ref->{response} : {};
        my $save_edits =
          (scalar keys %{ $arg_ref->{save_edits} } > 0) ? $arg_ref->{save_edits} : {};
        my $e_flag = undef;

# Storing mutant_info - Check if req mutant_info fields have been passed:
# if true: get mutant_class_id from param or max(mutant_class_id) + 1 from db or increment if it already exists in the edits table
# else: undef the 'mutant_class_id' associated with current locus_id (if any) and remove mutant_class_edits from anno_ref
        my $is_deleted           = 'N';
#        ($anno_ref, %save_edits) = get_feat_info(
#            {
#                table           => 'mutant_class',
#                cgi             => $cgi,
#                mutant_class_id => $mutant_class_id,
#                user_id         => $user_id,
#                anno_ref        => $anno_ref,
#                pick_edits      => \%save_edits
#            }
#        );

        my $mutant_class_hashref = {};
        ($mutant_class_hashref, $is_deleted) = selectrow_hashref(
            {
                table => 'mutant_class_edits',
                where => { mutant_class_id => $mutant_class_id, user_id => $anno_ref->{user_id} },
                edits => 1
            }
        );
        if (scalar keys %{$mutant_class_hashref} == 0) {
            $mutant_class_hashref = selectrow_hashref(
                { table => 'mutant_class', where => { mutant_class_id => $mutant_class_id } });
        }

        my $mutant_class_edits_hashref =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'mutant_class', id => undef });

        my $mutant_class_symbol = $cgi_params->{mutant_class_symbol};

        $e_flag = undef;
        ($mutant_class_edits_hashref, $save_edits->{mutant_class}, $e_flag) = cmp_db_hashref(
            {
                orig     => $mutant_class_hashref,
                edits    => $mutant_class_edits_hashref,
                is_admin => $anno_ref->{is_admin}
            }
        );
        $save_edits->{mutant_class} = 1
          if (defined $anno_ref->{is_admin} and defined $e_flag);

        $anno_ref->{mutant_class}->{$mutant_class_id} =
          ($save_edits->{mutant_class})
          ? $mutant_class_edits_hashref
          : $mutant_class_hashref;

        if (defined $save_edits->{mutant_class}) {
            if (defined $anno_ref->{is_admin}) {
                my $mutant_class_obj = selectrow(
                    {
                        table => 'mutant_class',
                        where => { mutant_class_id => $mutant_class_id }
                    }
                );

                if (not defined $mutant_class_obj) {
                    $mutant_class_obj =
                      do('insert', 'mutant_class', { mutant_class_id => $mutant_class_id, });
                }
                ($mutant_class_obj, $anno_ref->{mutant_class}->{$mutant_class_id}) = do(
                    'update',
                    'mutant_class',
                    {
                        hashref => $anno_ref->{mutant_class}->{$mutant_class_id},
                        obj     => $mutant_class_obj,
                    }
                );

                # delete the edits table entry (if exists)
                do('delete', 'mutant_class_edits',
                    { where => { mutant_class_id => $mutant_class_id } });

                # no longer define mutant_id as an edit in session
                $anno_ref->{mutant_class}->{$mutant_class_id}->{is_edit} = undef;

                $response->{'mutant_class_edits'} = undef;
            }
            else {
                my $mutant_class_edits_obj = selectrow(
                    {
                        table => 'mutant_class_edits',
                        where => {
                            mutant_class_id => $mutant_class_id,
                            user_id         => $anno_ref->{user_id}
                        }
                    }
                );

                if (defined $mutant_class_edits_obj) {
                    do(
                        'update',
                        'mutant_class_edits',
                        {
                            obj     => $mutant_class_edits_obj,
                            hashref => $anno_ref->{mutant_class}->{$mutant_class_id}
                        }
                    );
                }
                else {
                    $mutant_class_edits_obj = do(
                        'insert',
                        'mutant_class_edits',
                        {
                            mutant_class_id => $mutant_class_id,
                            user_id         => $anno_ref->{user_id},
                            edits => JSON::to_json($anno_ref->{mutant_class}->{$mutant_class_id}),
                            is_deleted => 'N'
                        }
                    );
                }

                $response->{'mutant_class_edits'} = 1;
            }
            $response->{'mutant_class_id'}      = $mutant_class_id;
            $response->{'updated_mutant_class'} = 1;
        }

        $arg_ref->{session}->param('anno_ref', $anno_ref);
        $arg_ref->{session}->flush;

        # HTML header
        #print $arg_ref->{session}->header(-type => 'text/plain');
        #? print "Update success! Changes submitted for administrator approval."
        #: print 'No changes to update.';

        $response->{'updated'} = (defined $save_edits->{mutant_class}) ? 1 : undef;

        if ($arg_ref->{mutant_class_id}) {
            return ($response, $save_edits, $anno_ref);
        }
        else {
            print $arg_ref->{session}->header(-type => 'application/json');

            print JSON::to_json($response);
        }
    }
    else {
        my $body_tmpl = HTML::Template->new(filename => "./tmpl/annotate_mutant_class.tmpl")
          if (not defined $arg_ref->{row});

        if (defined $arg_ref->{row}) {
            $arg_ref->{row}->{mutant_class_id} = $mutant_class_id;
            $arg_ref->{row}->{mutant_class_symbol} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol};
            $arg_ref->{row}->{mutant_class_name} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name};

            return $arg_ref->{row};
        }
        else {
            $body_tmpl->param(user_id => $anno_ref->{user_id});

            $body_tmpl->param(
                mutant_class_id     => $mutant_class_id,
                mutant_class_symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                mutant_class_name   => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name},
            );

            # HTML header
            print $arg_ref->{session}->header(-type => 'text/plain');

            print $body_tmpl->output;
        }
    }
}

sub delete_mutant_class {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_class_id = $cgi->param('mutant_class_id');

    # EXECUTE THE QUERY
    my $mutant_obj =
      selectrow({ table => 'mutant_class', where => { mutant_class_id => $mutant_class_id } });
    my $mutant_class_edits_obj = selectrow(
        {
            table => 'mutant_class_edits',
            where => { mutant_class_id => $mutant_class_id, user_id => $anno_ref->{user_id} },
            edits => 1
        }
    );

    my $response = {};
    $response->{deleted} = undef;

    my $is_deleted                 = undef;
    my $mutant_class_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $mutant_class_edits_obj) {
            ($mutant_class_edits_hashref, $is_deleted) = makerow_hashref(
                { obj => $mutant_class_edits_obj, table => 'mutant_class_edits', edits => 1 });

            $is_deleted = 'Y';

            $mutant_class_edits_obj = do(
                'update',
                'mutant_class_edits',
                {
                    hashref    => $mutant_class_edits_hashref,
                    obj        => $mutant_class_edits_obj,
                    is_deleted => $is_deleted
                }
            );
        }
        else {    # otherwise, create a new edits_obj, with empty `edits` field
            $is_deleted             = 'Y';
            $mutant_class_edits_obj = do(
                'insert',
                'mutant_class_edits',
                {
                    mutant_class_id => $mutant_class_id,
                    user_id         => $anno_ref->{user_id},
                    edits           => JSON::to_json($mutant_class_edits_hashref),
                    is_deleted      => $is_deleted
                }
            );
        }
        $response->{deleted} = 1;
    }
    else {    # delete mutant_obj and mutant_edits_obj if 'admin'
        $mutant_class_edits_obj->delete if (defined $mutant_class_edits_obj);

        delete $anno_ref->{mutant_class}->{$mutant_class_id};
        $response->{deleted} = 1;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    print JSON::to_json($response);
}

sub undelete_mutant_class {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_class_id = $cgi->param('mutant_class_id');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my $mutant_class_obj =
      selectrow({ table => 'mutant_class', where => { mutant_class_id => $mutant_class_id } });

    my $mutant_class_hashref = {};
    $mutant_class_hashref = makerow_hashref({ obj => $mutant_class_obj, table => 'mutant_class' })
      if (defined $mutant_class_obj);

    my $mutant_class_edits_obj = selectrow(
        {
            table => 'mutant_class_edits',
            where => { mutant_class_id => $mutant_class_id, user_id => $anno_ref->{user_id} },
            edits => 1
        }
    );

    my $is_deleted                 = undef;
    my $mutant_class_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $mutant_class_edits_obj) {
            ($mutant_class_edits_hashref, $is_deleted) = makerow_hashref(
                { obj => $mutant_class_edits_obj, table => 'mutant_class_edits', edits => 1 });

            $is_deleted = 'N';

            $mutant_class_edits_obj = do(
                'update',
                'mutant_class_edits',
                {
                    hashref    => $mutant_class_edits_hashref,
                    obj        => $mutant_class_edits_obj,
                    is_deleted => $is_deleted
                }
            );

            if (scalar keys %{$mutant_class_edits_hashref} == 0) {
                $mutant_class_edits_obj->delete;
                $anno_ref->{mutant_class}->{$mutant_class_id} = $mutant_class_hashref;
            }
            else {
                $anno_ref->{mutant_class}->{$mutant_class_id} = $mutant_class_edits_hashref;
            }
        }
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print 'Reverted!';
}

1;

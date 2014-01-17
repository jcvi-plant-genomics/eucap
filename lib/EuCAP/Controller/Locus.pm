package EuCAP::Controller::Locus;

use strict;
use EuCAP::DBHelper;
use EuCAP::Controller::Mutant;

use AnnotDB::DBHelper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(add_loci annotate_locus delete_locus undelete_locus);

sub add_loci {
    my ($session, $cgi) = @_;
    my $loci_list = $cgi->param('loci_list');
    my $anno_ref  = $session->param('anno_ref');

    my @new_loci  = split /,/, $loci_list;
    my $track     = 0;
    my @locus_ids = ();
  LOCUS: foreach my $gene_locus (@new_loci) {
        my $locus_id = undef;
        $gene_locus =~ s/\s+//gs;

        #next unless ($gene_locus =~ /^Medtr[1-8]g\d+|^\S+_\d+|^contig_\d+_\d+/);
        next
          unless ($gene_locus =~ /\bMedtr\d{1,}[gs]\d+\b/
            or $gene_locus =~ /\b\w{2}\d+_\d+\b/
            or $gene_locus =~ /\bcontig_\d+_\d+\b/);

        my $locus_obj = selectrow({ table => 'loci', where => { gene_locus => $gene_locus } });

        my $new_locus_obj;
        if (defined $locus_obj) {
            $locus_id = $locus_obj->locus_id;

            my $locus_edits_objs = selectall_iter('loci_edits', { locus_id => $locus_id });
            while (my $locus_edits_obj = $locus_edits_objs->next()) {
                next
                  unless ($locus_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($locus_edits_obj->is_deleted eq 'Y') {

                    # If not 'admin' user, allow user to re-add the locus
                    # else, delete the empty edits object, bring back
                    # the original entry and continue processing the
                    # input locus list
                    $locus_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                } elsif ($locus_edits_obj->family_id != $anno_ref->{family_id}) {
                    if (not defined $anno_ref->{is_admin}) {
                        do(
                            'update',
                            'loci_edits',
                            {
                                obj       => $locus_edits_obj,
                                family_id => $anno_ref->{family_id},
                            }
                        );

                        goto TRACK;
                    }
                }
                next LOCUS;
            }
        } else {
            my $is_deleted       = 'N';
            my $locus_edits_objs = selectall_iter('loci_edits');
            while (my $locus_edits_obj = $locus_edits_objs->next()) {
                my ($locus_edits_hashref, $is_deleted) =
                  makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });
                next unless ($locus_edits_hashref->{gene_locus} eq $gene_locus);

                $locus_id = $locus_edits_obj->locus_id;
                next
                  unless ($locus_edits_obj->user_id == $anno_ref->{user_id}
                    and not defined $anno_ref->{is_admin});

                if ($is_deleted eq 'Y') {
                    $locus_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                } elsif ($locus_edits_obj->family_id != $anno_ref->{family_id}) {
                    if (not defined $anno_ref->{is_admin}) {
                        do(
                            'update',
                            'loci_edits',
                            {
                                obj       => $locus_edits_obj,
                                family_id => $anno_ref->{family_id},
                            }
                        );

                        goto TRACK;
                    }
                }
                next LOCUS;
            }
        }

        # If not 'admin', get max(locus_id) after checking the 'loci'
        # and 'loci_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $locus_id = max_id({ table => 'loci' }) if (not defined $locus_id);
            warn "gene_locus: $gene_locus; locus_id: $locus_id";
        } else {    # else, insert new 'loci' row, get $locus_id and continue
            $new_locus_obj = do(
                'insert', 'loci',
                {
                    user_id   => $anno_ref->{user_id},
                    family_id => $anno_ref->{family_id},
                }
            );

            $locus_id = $new_locus_obj->locus_id;
        }

      INSERT:
        my $orig_func_annotation = get_original_annotation($gene_locus);
        my $gb_protein_acc = get_genbank_accession($gene_locus);

        $anno_ref->{loci}->{$locus_id}->{gene_locus}           = $gene_locus;
        $anno_ref->{loci}->{$locus_id}->{orig_func_annotation} = $orig_func_annotation;
        $anno_ref->{loci}->{$locus_id}->{gene_symbol}          = q{};
        $anno_ref->{loci}->{$locus_id}->{func_annotation}      = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc}       = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc}          = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_protein_acc}       = $gb_protein_acc;
        $anno_ref->{loci}->{$locus_id}->{reference_pub}        = q{};
        $anno_ref->{loci}->{$locus_id}->{mod_date}             = timestamp();
        $anno_ref->{loci}->{$locus_id}->{comment}              = q{};
        $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = 0;

        my $is_deleted = 'N';
        if (not defined $anno_ref->{is_admin}) {
            $anno_ref->{loci}->{$locus_id}->{is_edit} = 1;
            $new_locus_obj = do(
                'insert',
                'loci_edits',
                {
                    locus_id   => $locus_id,
                    user_id    => $anno_ref->{'user_id'},
                    family_id  => $anno_ref->{'family_id'},
                    edits      => JSON::to_json($anno_ref->{loci}->{$locus_id}),
                    is_deleted => $is_deleted
                }
            );
        } else {
            $new_locus_obj->set(
                gene_locus           => $gene_locus,
                orig_func_annotation => $orig_func_annotation,
                gene_symbol          => q{},
                func_annotation      => q{},
                gb_genomic_acc       => q{},
                gb_cdna_acc          => q{},
                gb_protein_acc       => $gb_protein_acc,
                reference_pub        => q{},
                mod_date             => $anno_ref->{loci}->{$locus_id}->{mod_date},
                comment              => q{},
                has_structural_annot => 0
            );
        }

      TRACK: $track++;

        push @locus_ids, $locus_id;

        #push @return_vals, JSON::to_json($anno_ref->{loci}->{$locus_id});
    }
    my $response = {};
    $response->{track}    = $track;
    $response->{locus_id} = \@locus_ids;

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    #print $session->header(-type => 'text/plain');
    print $session->header(-type => 'application/json');

    #annotate($session, $cgi);
    #print $track, ' loc', ($track >= 2 or $track == 0) ? 'i' : 'us', ' added!';
    print JSON::to_json($response);
}

sub annotate_locus {
    my ($arg_ref) = @_;

    my $locus_id = $arg_ref->{cgi}->param('locus_id');

    #gene_locus info should already be in the session.
    my $anno_ref = $arg_ref->{session}->param('anno_ref');
    my $user_id  = $anno_ref->{user_id};
    my $username = $anno_ref->{users}->{$user_id}->{username};

    if ($arg_ref->{save}) {
        my $response   = {};
        my $save_edits = {};

        # hashref to store a flag for each type of feature (loci, mutant_info, mutant_class)
        # used to track if there are changes or not

        # Storing loci is straightforward, there should already be a 'locus_id' for a newly instantiated gene.
        my $is_deleted    = 'N';
        my $locus_hashref = {};
        ($locus_hashref, $is_deleted) = selectrow_hashref(
            {
                table => 'loci_edits',
                where => { locus_id => $locus_id, user_id => $user_id },
                edits => 1
            }
        );
        if (scalar keys %{$locus_hashref} == 0) {
            $locus_hashref =
              selectrow_hashref({ table => 'loci', where => { locus_id => $locus_id } });
        }

        my $locus_edits_hashref =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'loci', id => undef });

        my $e_flag = undef;
        ($locus_edits_hashref, $save_edits->{loci}, $e_flag) = cmp_db_hashref(
            {
                orig     => $locus_hashref,
                edits    => $locus_edits_hashref,
                is_admin => $anno_ref->{is_admin}
            }
        );

        $save_edits->{loci} = 1 if (defined $anno_ref->{is_admin} and defined $e_flag);

        $anno_ref->{loci}->{$locus_id} =
          (defined $save_edits->{loci}) ? $locus_edits_hashref : $locus_hashref;

        my $cgi_params =
          cgi_to_hashref({ cgi => $arg_ref->{cgi}, table => 'cgi_mutant_info', id => undef });

      #$anno_ref->{loci}->{$locus_id}->{has_structural_annot} = $cgi_params->{has_structural_annot};

# Storing mutant_info - Check if req mutant_info fields have been passed:
# if true: get mutant_id from param or max(mutant_id) + 1 from db or increment if it already exists in the edits table
# else: undef the 'mutant_id' associated with current locus_id (if any) and remove mutant_edits from anno_ref
        my ($mutant_id, $mutant_class_id);
        if (    $cgi_params->{mutant_symbol} ne ""
            and $cgi_params->{mutant_class_symbol}  ne ""
            and $cgi_params->{mutant_class_name}    ne ""
            and $cgi_params->{mutant_phenotype}     ne ""
            and $cgi_params->{mutant_reference_pub} ne "")
        {
            ($response, $save_edits, $anno_ref) = annotate_mutant(
                {
                    save       => 1,
                    locus_id   => $locus_id,
                    cgi        => $arg_ref->{cgi},
                    session    => $arg_ref->{session},
                    anno_ref   => $anno_ref,
                    result     => $response,
                    save_edits => $save_edits,
                }
            );
        } else {
            if ($anno_ref->{loci}->{$locus_id}->{mutant_id} ne "") {
                my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

                $anno_ref->{loci}->{$locus_id}->{mutant_id} = undef;
                $save_edits->{loci} = 1;

                delete $anno_ref->{mutant_info}->{$mutant_id};

                my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};
                delete $anno_ref->{mutant_class}->{$mutant_class_id}
                  if (defined $mutant_class_id);
            }
        }

        #save current value to db if save flag set
        if (defined $save_edits->{loci}) {

            # if logged in as administrator, update/insert into main tables.
            $anno_ref->{loci}->{$locus_id}->{mod_date} = timestamp();
            if (defined $anno_ref->{is_admin}) {
                my $locus_obj = selectrow({ table => 'loci', where => { locus_id => $locus_id } });

                if (not defined $locus_obj) {
                    $locus_obj = do(
                        'insert', 'loci',
                        {
                            locus_id  => $locus_id,
                            user_id   => $anno_ref->{user_id},
                            family_id => $anno_ref->{family_id},
                        }
                    );
                }
                ($locus_obj, $anno_ref->{loci}->{$locus_id}) = do(
                    'update', 'loci',
                    {
                        hashref => $anno_ref->{loci}->{$locus_id},
                        obj     => $locus_obj,
                    }
                );

                # delete the edits table entry (if exists)
                do('delete', 'loci_edits', { where => { locus_id => $locus_id } });

                # no longer define locus_id as an edit in session
                $anno_ref->{loci}->{$locus_id}->{is_edit} = undef;

                $response->{'locus_edits'} = undef;
            } else {

                # if not admin, update/insert into edits tables
                my $locus_edits_obj =
                  selectrow({ table => 'loci_edits', where => { locus_id => $locus_id } });

                if (defined $locus_edits_obj) {
                    $locus_edits_obj = do(
                        'update',
                        'loci_edits',
                        {
                            hashref => $anno_ref->{loci}->{$locus_id},
                            obj     => $locus_edits_obj,
                        }
                    );
                } else {
                    $locus_edits_obj = do(
                        'insert',
                        'loci_edits',
                        {
                            locus_id   => $locus_id,
                            user_id    => $anno_ref->{user_id},
                            family_id  => $anno_ref->{family_id},
                            edits      => JSON::to_json($anno_ref->{loci}->{$locus_id}),
                            is_deleted => $is_deleted
                        }
                    );
                }
                $response->{'locus_edits'} = 1;
            }

            $response->{'locus_id'} = $locus_id;
            $response->{'mod_date'} = $anno_ref->{loci}->{$locus_id}->{mod_date};
        }

        $arg_ref->{session}->param('anno_ref', $anno_ref);
        $arg_ref->{session}->flush;

        # HTML header
        #print $arg_ref->{session}->header(-type => 'text/plain');
        print $arg_ref->{session}->header(-type => 'application/json');

        $response->{'updated'} = (
                 defined $save_edits->{loci}
              or defined $save_edits->{mutant_info}
              or defined $save_edits->{mutant_class}
        ) ? 1 : undef;

        #? print "Update success! Changes submitted for administrator approval."
        #: print 'No changes to update.';

        print JSON::to_json($response);
    } else {

        #output the session
        #$row = $anno_ref->{loci}->{$locus_id};
        my $annotate_locus_loop = [];
        my @locus_ids = split /,/, $locus_id;

        my $body_tmpl =
          ($arg_ref->{action} eq "annotate_locus")
          ? HTML::Template->new(filename => "./tmpl/annotate_locus.tmpl")
          : HTML::Template->new(filename => "./tmpl/view_locus.tmpl", die_on_bad_params => 0);

        foreach my $locus_id (sort { $a <=> $b } @locus_ids) {
            my $locus_row = {};
            $locus_row = {
                gene_symbol          => $anno_ref->{loci}->{$locus_id}->{gene_symbol},
                gene_locus           => $anno_ref->{loci}->{$locus_id}->{gene_locus},
                func_annotation      => $anno_ref->{loci}->{$locus_id}->{func_annotation},
                orig_func_annotation => $anno_ref->{loci}->{$locus_id}->{orig_func_annotation},

                comment        => $anno_ref->{loci}->{$locus_id}->{comment},
                gb_genomic_acc => $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc},
                gb_cdna_acc    => $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc},
                gb_protein_acc => $anno_ref->{loci}->{$locus_id}->{gb_protein_acc},

                reference_pub        => $anno_ref->{loci}->{$locus_id}->{reference_pub},
                mutant_id            => $anno_ref->{loci}->{$locus_id}->{mutant_id},
                mod_date             => $anno_ref->{loci}->{$locus_id}->{mod_date},
                has_structural_annot => $anno_ref->{loci}->{$locus_id}->{has_structural_annot},

                locus_id => $locus_id,
                username => ($arg_ref->{action} eq "annotate_locus") ? $username : "",
            };

            if ($arg_ref->{action} eq "annotate_locus") {
                if (defined $anno_ref->{is_admin}) {
                    $locus_row->{gene_symbol_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{gene_symbol_edit});
                    $locus_row->{func_annotation_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{func_annotation_edit});
                    $locus_row->{comment_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{comment_edit});
                    $locus_row->{gb_genomic_acc_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc_edit});
                    $locus_row->{gb_cdna_acc_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc_edit});
                    $locus_row->{gb_protein_acc_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{gb_protein_acc_edit});
                    $locus_row->{reference_pub_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{reference_pub_edit});
                    $locus_row->{mutant_id_edit} = 1
                      if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id_edit});
                }
            }

            $locus_row->{annotate_mutant_loop} = [];

            if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
                and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
            {
                my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};
                if (not defined $anno_ref->{mutant_info}->{$mutant_id}->{is_deleted}) {
                    $locus_row = annotate_mutant(
                        { mutant_id => $mutant_id, anno_ref => $anno_ref, row => $locus_row });
                }
            } else {
                my $annotate_mutant_loop = [];
                my $mutant_row           = {};

                $mutant_row = {
                    user_id => $anno_ref->{user_id},
                    locus_id => $locus_id
                };
                push @$annotate_mutant_loop, $mutant_row;
                $locus_row->{annotate_mutant_loop} = $annotate_mutant_loop;
            }

            push @$annotate_locus_loop, $locus_row;
        }

        $body_tmpl->param(annotate_locus_loop => $annotate_locus_loop);

        #delete $row->{is_edit};         # hack: ignore the 'is_edit' hashref key

        # HTML header
        print $arg_ref->{session}->header(-type => 'text/plain');

        print $body_tmpl->output;
    }
}

sub delete_locus {
    my ($session, $cgi) = @_;

    my $locus_id = $cgi->param('locus_id');
    my $anno_ref = $session->param('anno_ref');

    my $response = {};
    $response->{deleted} = undef;

    # EXECUTE THE QUERY
    my $locus_obj = selectrow({ table => 'loci', where => { locus_id => $locus_id } });
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        my $locus_edits_obj = selectrow(
            {
                table => 'loci_edits',
                where => { locus_id => $locus_id, user_id => $anno_ref->{user_id} }
            }
        );

        my $is_deleted          = undef;
        my $locus_edits_hashref = {};
        if (defined $locus_edits_obj) {
            ($locus_edits_hashref, $is_deleted) =
              makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });
            $is_deleted = 'Y';

            $locus_edits_obj = do(
                'update',
                'loci_edits',
                {
                    hashref    => $locus_edits_hashref,
                    obj        => $locus_edits_obj,
                    is_deleted => $is_deleted
                }
            );
        } else {    # otherwise, create a new edits_obj, with empty `edits` field
            $is_deleted      = 'Y';
            $locus_edits_obj = do(
                'insert',
                'loci_edits',
                {
                    locus_id   => $locus_id,
                    family_id  => $anno_ref->{family_id},
                    user_id    => $anno_ref->{user_id},
                    edits      => JSON::to_json($locus_edits_hashref),
                    is_deleted => $is_deleted
                }
            );
        }
        $response->{deleted} = 1;
    } else {    # delete locus_obj and locus_edits_obj if 'admin'
        $locus_obj->delete if (defined $locus_obj);

        my $locus_edits_objs = selectall_iter('loci_edits', { locus_id => $locus_id });
        while (my $locus_edits_obj = $locus_edits_objs->next()) {
            $locus_edits_obj->delete if (defined $locus_edits_obj);
        }

        delete $anno_ref->{loci}->{$locus_id};
        $response->{deleted} = 1;
    }

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print JSON::to_json($response);
}

sub undelete_locus {
    my ($session, $cgi) = @_;

    my $locus_id = $cgi->param('locus_id');
    my $anno_ref = $session->param('anno_ref');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my $locus_hashref = {};
    my $locus_obj = selectrow({ table => 'loci', where => { locus_id => $locus_id } });
    $locus_hashref = makerow_hashref({ obj => $locus_obj, table => 'loci' })
      if (defined $locus_obj);

    my $locus_edits_obj = selectrow(
        {
            table => 'loci_edits',
            where => { locus_id => $locus_id, user_id => $anno_ref->{user_id} }
        }
    );

    my $is_deleted          = 'N';
    my $locus_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $locus_edits_obj) {
            ($locus_edits_hashref, $is_deleted) =
              makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });

            $is_deleted = 'N';

            $locus_edits_obj = do(
                'update',
                'loci_edits',
                {
                    hashref    => $locus_edits_hashref,
                    obj        => $locus_edits_obj,
                    is_deleted => $is_deleted
                }
            );
        }

        if (scalar keys %{$locus_edits_hashref} == 0) {
            $locus_edits_obj->delete;
            $anno_ref->{loci}->{$locus_id} = $locus_hashref;
        } else {
            $anno_ref->{loci}->{$locus_id} = $locus_edits_hashref;
        }
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    print 'Reverted!';
}

1;

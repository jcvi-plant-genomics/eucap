package EuCAP::Controller::Submit;

use strict;
use EuCAP::DBHelper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(review_annotation submit_annotation);

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# Build the Project Annotatotr (PA) and Admin email addresses
my $email_domain = $cfg{'email'}{'domain'};
my $PA           = $cfg{'email'}{'pa'};
my $admin        = $cfg{'email'}{'admin'};

my $PA_address    = $PA . "\@" . $email_domain;
my $admin_address = $admin . "\@" . $email_domain;

sub review_annotation {
    my ($session, $cgi) = @_;

    my $body_tmpl = HTML::Template->new(
        filename          => "./tmpl/review_annotation.tmpl",
        die_on_bad_params => 0
    );
    my $anno_ref = $session->param('anno_ref');

    my $user_id   = $anno_ref->{user_id};
    my $family_id = $anno_ref->{family_id};
    my %all_loci  = selectall_id(
        {
            table      => 'loci',
            where      => { user_id => $anno_ref->{user_id}, family_id => $family_id },
            is_deleted => 'N'
        }
    );

    # loop through each locus_id and investigate associated mutants/alleles
    my %deleted_loci = ();
    my %unapproved_loci = ();
    my $review_loop = [];
    foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
        my %pick_edits = ();

        ($anno_ref, $pick_edits{loci}, $unapproved_loci{$locus_id}, $deleted_loci{$locus_id}) = get_feat_info(
            {
                table      => 'loci',
                locus_id   => $locus_id,
                user_id    => $user_id,
                anno_ref   => $anno_ref,
                extra_flags => 1
            }
        );

        next if (defined $deleted_loci{$locus_id});

        my $row = $anno_ref->{loci}->{$locus_id};
        my $mutant_id = $row->{mutant_id};

        if ($mutant_id) {
            ($anno_ref, $pick_edits{mutant_info}) = get_feat_info(
                {
                    table      => 'mutant_info',
                    mutant_id  => $mutant_id,
                    user_id    => $user_id,
                    anno_ref   => $anno_ref,
                }
            );

            $row->{mutant_symbol} = $anno_ref->{mutant_info}->{$mutant_id}->{symbol};
        }

        push(@$review_loop, $row);

    }
    $body_tmpl->param(
        review_loop => $review_loop,
        family_name => $anno_ref->{family}->{$family_id}->{family_name}
    );
    print $session->header;

    print $body_tmpl->output;
}

sub submit_annotation {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $family_name = $cgi->param('family_name');

    my $body_tmpl = HTML::Template->new(filename => "./tmpl/email_body_submit.tmpl");
    $body_tmpl->param(family_name => $family_name);
    my $email_body = $body_tmpl->output;

    my $user_id = $anno_ref->{user_id};
    my $success = send_email(
        {
            to_addr  => $anno_ref->{users}->{$user_id}->{email},
            cc_addr  => $PA_address,
            bcc_addr => $admin_address,
            subject  => "[EuCAP] $family_name Gene Family Annotation Submission",
            body     => $email_body
        }
    );

    print $cgi->header(-type => 'application/json');
    my $response =
      ($success)
      ? {
        'success' => 1,
        'message' =>
'Success! Please check your email for confirmation.<br />You may <a href="/cgi-bin/eucap/eucap.pl?action=logout">log out</a> of the system now.'
      }
      : { 'success' => undef, 'message' => 'Error: Please notify website administrator' };

    print JSON::to_json($response);
}

1;

#!/usr/local/bin/perl

use warnings;
use strict;

# Set the perl5lib path variable
BEGIN {
    unshift @INC, '../', './lib', './lib/5.16.1', '../textpresso';
}

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# CGI and authentication related modules
use CGI;
use CGI::Carp qw( fatalsToBrowser );
use CGI::Session;
use Digest;
use Authen::Passphrase::MD5Crypt;

# Page rendering Template modules
use Template;
use HTML::Template;

# Data related modules
use URI;
use JSON;
use IO::String;
use Image::Size;
use File::Copy;
use File::Basename;
use Data::Dumper;
use Time::Piece;
use Config::IniFiles;

# Parameter Validation
use Params::Validate;

# DB related modules
use DBI;

# Annotation Database helper module
use AnnotDB::DBHelper;

# Textpresso modules
use Textpresso::Helper;

# EuCAP modules (M-V-C)
# Model
use EuCAP::DBHelper;
use EuCAP::API;
use EuCAP::Registration;
use EuCAP::Contact;

# Controller
use EuCAP::Controller::Locus;
use EuCAP::Controller::Mutant_class;
use EuCAP::Controller::Mutant;
use EuCAP::Controller::Allele;
use EuCAP::Controller::Structural_annot;
use EuCAP::Controller::User;
use EuCAP::Controller::Submit;

# View
use EuCAP::Print_to_screen;

# Supporting Apps
use EuCAP::Apps::Blast;

# Third-party modules
use Digest::MD5 qw/md5 md5_hex md5_base64/;
use MIME::Base64 qw/encode_base64url/;

# Allow max 1MB upload size
$CGI::POST_MAX = 1024 * 1000;

# Describe safe file name characters (no spaces or symbols allowed)
my $safe_filename_characters = "a-zA-Z0-9_.-";

# Initialize some variables
my $page_vars = {};
my $FLAG      = 0;

# actions that do not require session validation (no login necessary)
my %actions_nologin = (
    "signup_page"          => 1,
    "signup_user"          => 1,
    "validate_new_user"    => 1,
    "check_username"       => 1,
    "check_email"          => 1,
    "get_loci"             => 1,
    "get_mutant_info"      => 1,
    "get_pmids"            => 1,
    "retrieve_pmid_record" => 1,
);

my $WEBTIER = ($ENV{'WEBTIER'} =~ /dev/) ? "dev" : "prod";
# Local community annotation DB connection params
my $CA_DB_NAME = $cfg{'eucap'}{'database'};
my $CA_SERVER  = 'eucap-' . $WEBTIER;
my ($CA_DB_USERNAME, $CA_DB_PASSWORD, $CA_DB_HOST) =
  ($cfg{$CA_SERVER}{'username'}, $cfg{$CA_SERVER}{'password'}, $cfg{$CA_SERVER}{'hostname'});
my $CA_DB_DSN = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));

# Need this dbh for CGI::Session
my $ca_dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD)
  or die("cannot connect to CA database:$!");

my $cgi    = CGI->new;
my $action = $cgi->param('action');

my $session;
CGI::Session->name("Medicago_EuCAP");
$session = CGI::Session->load("driver:mysql", $cgi, { Handle => $ca_dbh })
  or die(CGI::Session->errstr . "\n");

if ($action) {
    if (not defined $actions_nologin{$action}) {
        if ($session->is_expired) {
            print $session->header(), $cgi->start_html(),
              $cgi->p("Your session timed out! Refresh the screen to start a new session!"),
              $cgi->end_html();
            exit(0);
        } elsif ($session->is_empty) {
            $session = CGI::Session->new("driver:mysql", $cgi, { Handle => $ca_dbh })
              or die(CGI::Session->errstr . "\n");
        }

        init($session, $cgi);
        $session->flush;
    }
} else {
    $action = ($session->param('~logged_in')) ? "dashboard" : "login_page";
}

# Based on the hidden CGI parameter 'action',
# decide what page/content is to be rendered
if ($action eq "login_page") {
    $page_vars = login_page({
        'cgi' => $cgi,
    });
} elsif ($action eq 'signup_page') {
    $page_vars = signup_page($cgi);
} elsif ($action eq 'signup_user') {
    signup_user($cgi);
    $FLAG = 1;
} elsif ($action eq 'validate_new_user') {
    validate_new_user($cgi);
} elsif ($action eq 'dashboard') {
    dashboard($session, $cgi);
} elsif ($action eq 'edit_profile') {
    $page_vars = edit_profile($session, $cgi);
} elsif ($action eq 'update_profile') {
    edit_profile($session, $cgi, 1);
    $FLAG = 1;
} elsif ($action eq 'update_password') {
    update_password($session, $cgi);
    $FLAG = 1;
}

# Locus/mutant specific actions
elsif ($action eq 'annotate') {
    annotate($session, $cgi, 'loci');
} elsif ($action eq 'annotate_locus' or $action eq 'view_locus' or $action eq 'save_locus') {
    my $save = ($action eq 'save_locus') ? 1 : undef;

    annotate_locus(
        {
            session => $session,
            cgi     => $cgi,
            action  => $action,
            save    => $save
        }
    );
    $FLAG = 1;
} elsif ($action eq 'add_loci') {
    add_loci($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'get_loci') {
    my $app        = $cgi->param('app');
    my $gene_locus = $cgi->param('term');
    my $limit      = (defined $cgi->param('limit')) ? $cgi->param('limit') : 25;

    get_loci({ cgi => $cgi, gene_locus => $gene_locus, limit => $limit, app => $app });
    $FLAG = 1;
} elsif ($action eq 'delete_locus') {
    delete_locus($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'undelete_locus') {
    undelete_locus($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'run_blast') {
    run_blast($session, $cgi);
    $FLAG = 1;
}

# Mutant class specific actions
elsif ($action eq 'add_mutant_class_dialog') {
    add_mutant_class($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'add_mutant_class') {
    add_mutant_class($session, $cgi, 1);
    $FLAG = 1;
} elsif ($action eq 'annotate_mutant_class') {
    annotate_mutant_class(
        {
            session => $session,
            cgi     => $cgi
        }
    );
    $FLAG = 1;
} elsif ($action eq 'save_mutant_class') {
    annotate_mutant_class(
        {
            session => $session,
            cgi     => $cgi,
            save    => 1
        }
    );
    $FLAG = 1;
} elsif ($action eq 'delete_mutant_class') {
    delete_mutant_class($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'undelete_mutant_class') {
    undelete_mutant_class($session, $cgi);
    $FLAG = 1;
}

# Mutant-specific actions
elsif ($action eq 'annotate_mutants') {
    annotate($session, $cgi, 'mutants');
} elsif ($action eq 'add_mutants') {
    add_mutants($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'annotate_mutant') {
    annotate_mutant(
        {
            session => $session,
            cgi     => $cgi
        }
    );
    $FLAG = 1;
} elsif ($action eq 'save_mutant') {
    annotate_mutant(
        {
            session => $session,
            cgi     => $cgi,
            save    => 1
        }
    );
    $FLAG = 1;
} elsif ($action eq 'delete_mutant') {
    delete_mutant($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'undelete_mutant') {
    undelete_mutant($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'get_mutant_info') {
    my $mutant_sym = $cgi->param('term');
    my $limit      = (defined $cgi->param('limit')) ? $cgi->param('limit') : 10;
    my $edits      = (defined $cgi->param('edits')) ? $cgi->param('edits') : undef;
    my $user_id    = (defined $cgi->param('user_id')) ? $cgi->param('user_id') : undef;

    get_mutant_info(
        {
            cgi     => $cgi,
            symbol  => $mutant_sym,
            limit   => $limit,
            user_id => $user_id,
            edits   => $edits
        }
    );
    $FLAG = 1;
}

# Allele-specific actions
elsif ($action eq 'annotate_alleles') {
    annotate_alleles($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'save_alleles') {
    annotate_alleles($session, $cgi, 1);
    $FLAG = 1;
} elsif ($action eq 'add_alleles') {
    add_alleles($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'delete_allele') {
    delete_allele($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'undelete_allele') {
    undelete_allele($session, $cgi);
    $FLAG = 1;
}

# Structural annotation specific actions
elsif ($action eq 'struct_anno') {
    structural_annotation($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'submit_struct_anno') {
    submit_structural_annotation($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'review_annotation') {
    review_annotation($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'submit_annotation') {
    submit_annotation($session, $cgi);
    $FLAG = 1;
} elsif ($action eq 'final_submit') {
    final_submit($session, $cgi);
} elsif ($action eq 'check_username') {
    my $username = $cgi->param('username');
    my $user_id  = (defined $cgi->param('user_id')) ? $cgi->param('user_id') : undef;
    my $ignore   = (defined $cgi->param('ignore')) ? $cgi->param('ignore') : undef;

    check_username($cgi, $username, $user_id, $ignore);
    $FLAG = 1;
} elsif ($action eq 'check_email') {
    my $email = $cgi->param('email');
    my $ignore = (defined $cgi->param('ignore')) ? $cgi->param('ignore') : undef;

    check_email($cgi, $email, $ignore);
    $FLAG = 1;
}

# publication specific actions
elsif ($action eq 'get_pmids') {
    my $pmid = $cgi->param('term');

    get_pmids({ cgi => $cgi, pmid => $pmid }) if ($pmid !~ /\D+/);
    $FLAG = 1;
} elsif ($action eq 'retrieve_pmid_record') {
    my $pmid = $cgi->param('term');

    retrieve_pmid_record({ cgi => $cgi, pmid => $pmid }) if ($pmid !~ /\D+/);
    $FLAG = 1;
} elsif ($action eq 'logout') {
    $page_vars = logout($session, $cgi);
}
#else {    # logged in and fall through the actions - then log out
#    logout($session, $cgi, 'Sorry! System error. Please report issue to site administrator.');
#}

# $FLAG == 0 corresponds to any option resulting in a complete page reload
# $FLAG == 1 corresponds to an asynchronous requests returing JSON/HTML/PLAINTEXT
PROCESS_TMPL: if (!$FLAG) {
    output_to_page_tmpl($page_vars);
}

$ca_dbh->disconnect if $ca_dbh;

# EuCAP subroutines
sub init {
    my ($session, $cgi) = @_;
    if ($session->param('~logged_in')) {
        return 1;
    }

    unless ($action) {
        $page_vars = login_page({
            'cgi' => $cgi,
        });
        goto PROCESS_TMPL;
    }

    my $username = $cgi->param('username');
    my $password = $cgi->param('passwd');
    my $user     = selectrow({ table => 'users', where => { username => $username } });
    if (!$user) {
        $page_vars = login_page({
            'cgi' => $cgi,
            'is_error_msg' => 1,
            'error_string' => "User name not found. Please check and try again."
        });
        goto PROCESS_TMPL;
    }

    my $salt      = $user->salt;
    my $hash      = $user->hash;
    my $crypt_obj = Authen::Passphrase::MD5Crypt->new(salt => $salt, hash_base64 => $hash);
    if ($crypt_obj->match($password)) {
        $session->param('~logged_in', 1);    # authenticated

        #store user_id as a CGI::session param
        my $anno_ref = {};
        if ($username eq "admin") {
            $anno_ref->{is_admin}         = 1;
            $anno_ref->{is_family_editor} = 1;
        } else {
            $anno_ref->{user_id} = $user->user_id;
            my @fams = selectall_array('family', { user_id => $anno_ref->{user_id} });
            $anno_ref->{is_family_editor} = (scalar @fams >= 1) ? 1 : undef;
        }

        $session->param('anno_ref', $anno_ref);
        $session->flush;

        return 0;
    } else {
        $page_vars = login_page({
            'cgi' => $cgi,
            'is_error_msg' => 1,
            'error_string' => "Password does not match! Please check and try again."
        });
        $session->delete();
        $session->flush;
        goto PROCESS_TMPL;
    }
}

sub dashboard {
    my ($session, $cgi) = @_;
    my $title     = "Annotator Dashboard";
    my $body_tmpl = HTML::Template->new(filename => "./tmpl/dashboard.tmpl");
    my $anno_ref  = $session->param('anno_ref');

    my $user_id = (defined $anno_ref->{is_admin}) ? 0 : $anno_ref->{user_id};
    $anno_ref = update_session(
        { table => 'users', id => $user_id, anno_ref => $anno_ref, session => $session });
    my $username = $anno_ref->{users}->{$user_id}->{username};

    my @fams =
      ($username eq "admin")
      ? selectall_array('family')
      : selectall_array('family', { user_id => $user_id });

    ## Populate the 'Annotate Gene Families' section of the Dashboard menu
    my $disabled         = undef;
    my $gene_family_list = [];
    if (scalar @fams == 0)
    {    # if the user does not have any associated gene families, disable this seciton
        $disabled = 1;
    } else {    # loop through all gene families for the current user_id
        foreach my $fam (@fams) {
            my $family_id = $fam->family_id;

            my $edits = 0;
            if (defined $anno_ref->{is_admin}) {
                my @loci_edits_objs = selectall_array('loci_edits', { family_id => $family_id });
                $edits = scalar @loci_edits_objs;
            }

            my $row = {
                family_id         => $family_id,
                gene_class_symbol => $fam->gene_class_symbol,
                family_name       => $fam->family_name,
                description       => (defined $anno_ref->{is_admin}) ? $edits : $fam->description
            };
            push @$gene_family_list, $row;

  #            if (not defined $anno_ref->{is_admin}) {
  #                $anno_ref->{family_id}                                 = $family_id;
  #                $anno_ref->{family}->{$family_id}->{family_name}       = $fam->family_name;
  #                $anno_ref->{family}->{$family_id}->{gene_class_symbol} = $fam->gene_class_symbol;
  #                $anno_ref->{family}->{$family_id}->{description}       = $fam->description;
  #            }
        }
        $body_tmpl->param(gene_family_radio => $gene_family_list);
    }

    ## Populate the 'Annotate Gene Loci' section of the Dashboard accordion menu
    my $locus_select_list = [];
    my %all_loci          = selectall_id(
        {
            table   => 'loci',
            user_id => $user_id,
        }
    );

    # loop through each locus_id (both approved and unapproved)
    my $i = 0;

    my %pick_edits      = ();
    my %deleted_loci    = ();
    my %unapproved_loci = ();

    my $locus_summary_loop         = [];
    my $deleted_locus_summary_loop = [];
    foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
        ($anno_ref, $pick_edits{loci}, $unapproved_loci{$locus_id}, $deleted_loci{$locus_id}) =
          get_feat_info(
            {
                table       => 'loci',
                locus_id    => $locus_id,
                user_id     => $user_id,
                anno_ref    => $anno_ref,
                extra_flags => 1
            }
          );

        ++$i;
        my $select_row = {
            locus_id        => $locus_id,
            gene_locus      => $anno_ref->{loci}->{$locus_id}->{gene_locus},
            func_annotation => $anno_ref->{loci}->{$locus_id}->{orig_func_annotation},
            gene_symbol     => $anno_ref->{loci}->{$locus_id}->{gene_symbol},
            disabled        => (defined $deleted_loci{$locus_id}) ? 1 : undef
        };

        push @$locus_select_list, $select_row;

        my $summary_row = {};

        if (defined $unapproved_loci{$locus_id} or defined $deleted_loci{$locus_id}) {
            $summary_row->{locus_id}   = $locus_id;
            $summary_row->{gene_locus} = $anno_ref->{loci}->{$locus_id}->{gene_locus};
            $summary_row->{orig_func_annotation} =
              $anno_ref->{loci}->{$locus_id}->{orig_func_annotation};
            $summary_row->{gene_symbol}   = $anno_ref->{loci}->{$locus_id}->{gene_symbol};
            $summary_row->{tableRowClass} = "info"
              if (  defined $anno_ref->{is_admin}
                and defined $anno_ref->{loci}->{$locus_id}->{is_edit});

            if (defined $deleted_loci{$locus_id}) {
                push @$deleted_locus_summary_loop, $summary_row;
            } else {
                push @$locus_summary_loop, $summary_row;
            }
        }
    }

    $body_tmpl->param(
        locus_select_list          => $locus_select_list,
        locus_summary_loop         => $locus_summary_loop,
        deleted_locus_summary_loop => $deleted_locus_summary_loop,
    );

    ## Populate the 'Annotate Mutants' section of the Dashboard accordion menu
    my $mutant_class_list         = [];
    my $deleted_mutant_class_list = [];

    my $where_ref = {};
    my %mutant_class_ids = selectall_id({ table => 'mutant_class' });

    my %deleted_mutant_class    = ();
    my %unapproved_mutant_class = ();
    foreach my $mutant_class_id (sort { $a <=> $b } keys %mutant_class_ids) {
        (
            $anno_ref,
            $pick_edits{mutant_class},
            $unapproved_mutant_class{$mutant_class_id},
            $deleted_mutant_class{$mutant_class_id}
          )
          = get_feat_info(
            {
                table           => 'mutant_class',
                mutant_class_id => $mutant_class_id,
                user_id         => $user_id,
                anno_ref        => $anno_ref,
                extra_flags     => 1
            }
          );

        my ($mutant_class_sym, $mutant_class_name) = (
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
        );

        my $row = {
            mutant_class_id     => $mutant_class_id,
            mutant_class_symbol => $mutant_class_sym,
            mutant_class_name   => $mutant_class_name,
            num_mutants         => count_features(
                {
                    table   => 'mutant_info',
                    where   => { mutant_class_id => $mutant_class_id },
                    user_id => $user_id
                }
            ),
            user_id => $user_id,
        };
        $row->{unapproved} = 1 if (defined $unapproved_mutant_class{$mutant_class_id});

        if (defined $deleted_mutant_class{$mutant_class_id}) {
            push @$deleted_mutant_class_list, $row;
        } else {
            push @$mutant_class_list, $row;
        }
    }

    $body_tmpl->param(
        user_id                   => $user_id,
        mutant_class_list         => $mutant_class_list,
        deleted_mutant_class_list => $deleted_mutant_class_list,
        disabled                  => $disabled,
    );

    $body_tmpl->param(family_panel => 1)
      if (not defined $cgi->param('loci_panel') and not defined $cgi->param('mutant_panel'));
    $body_tmpl->param(loci_panel => 1)
      if ((defined $cgi->param('loci_panel') or $disabled)
        and not defined $cgi->param('mutant_panel'));
    $body_tmpl->param(mutant_panel => 1)
      if (defined $cgi->param('mutant_panel') and not defined $cgi->param('loci_panel'));

    delete $anno_ref->{family};
    delete $anno_ref->{family_id};

    if (defined $anno_ref->{is_admin}) {
        $body_tmpl->param(is_admin => 1);

        delete $anno_ref->{loci};
        delete $anno_ref->{mutant_info};
        delete $anno_ref->{mutant_class};
        delete $anno_ref->{alleles};
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header;

    push @{ $page_vars->{javascripts} }, "/eucap/include/js/annotate.js",
      "/eucap/include/js/jquery.qtip.min.js",
      "/eucap/include/js/jquery.quicksearch.js",
      "/eucap/include/js/jquery.multi-select.js",
      "/eucap/include/js/jquery.tagsinput.js",
      "/eucap/include/js/jquery.selectBox.min.js",
      "/eucap/include/js/textpresso.js";

    push @{ $page_vars->{stylesheets} }, "/eucap/include/css/jquery.qtip.css",
      "/eucap/include/css/jquery.multi-select.css",
      "/eucap/include/css/jquery.tagsinput.css",
      "/eucap/include/css/jquery.selectBox.css";

    push @{ $page_vars->{breadcrumb} }, ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => $title });
    $page_vars->{title}            = "EuCAP :: $title";
    $page_vars->{page_header}      = "Annotator Dashboard";
    $page_vars->{is_family_editor} = 1 if (defined $anno_ref->{is_family_editor});

    $page_vars->{user_info} = {
        'username'     => $username,
        'name'         => $anno_ref->{users}->{$user_id}->{name},
        'organization' => $anno_ref->{users}->{$user_id}->{organization},
        'email'        => $anno_ref->{users}->{$user_id}->{email},
        'url'          => $anno_ref->{users}->{$user_id}->{url},
        'email_hash'   => md5_hex($anno_ref->{users}->{$user_id}->{email}),
    };
    $page_vars->{main_content} = $body_tmpl->output;
}

sub annotate {
    my ($session, $cgi, $feature) = @_;
    my $body_tmpl = HTML::Template->new(filename => "./tmpl/annotate.tmpl", die_on_bad_params => 0);
    my $anno_ref = $session->param('anno_ref');

    my $user_id;
    my ($title, $username) = ("", "");
    if ($feature eq 'loci') {
        my $family_id;
        ($user_id, $family_id) = ($anno_ref->{user_id}, $cgi->param('family_id'));

        $anno_ref = update_session(
            {
                table    => 'family',
                id       => $family_id,
                anno_ref => $anno_ref,
                session  => $session
            }
        );

        $username =
          (defined $anno_ref->{is_admin})
          ? "admin"
          : $anno_ref->{users}->{$user_id}->{username};

        $title =
          'Annotate ' . $anno_ref->{family}->{$family_id}->{gene_class_symbol} . ' Gene Family';

       # coming in from the select family action - the database is the most up to data source
       # count the number of loci for this family (unique of all loci in the original & edits table)
        my %all_loci = selectall_id(
            {
                table   => 'loci',
                where   => { family_id => $anno_ref->{family_id} },
                user_id => $anno_ref->{user_id}
            }
        );

        # loop through each locus_id and investigate associated mutants/alleles
        my %deleted_loci    = ();
        my %unapproved_loci = ();
        foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
            my %pick_edits = ();

            ($anno_ref, $pick_edits{loci}, $unapproved_loci{$locus_id}, $deleted_loci{$locus_id}) =
              get_feat_info(
                {
                    table       => 'loci',
                    locus_id    => $locus_id,
                    user_id     => $user_id,
                    anno_ref    => $anno_ref,
                    extra_flags => 1
                }
              );

            if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
                and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
            {
                my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

                ($anno_ref, $pick_edits{mutant_info}) = get_feat_info(
                    {
                        table     => 'mutant_info',
                        mutant_id => $mutant_id,
                        user_id   => $user_id,
                        anno_ref  => $anno_ref,
                    }
                );

                $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles} = count_features(
                    {
                        table   => 'alleles',
                        where   => { mutant_id => $mutant_id },
                        user_id => $user_id
                    }
                );

                my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

                ($anno_ref, $pick_edits{mutant_class}) = get_feat_info(
                    {
                        table           => 'mutant_class',
                        mutant_class_id => $mutant_class_id,
                        user_id         => $user_id,
                        anno_ref        => $anno_ref,
                    }
                );
            }
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        #now output the session
        my $locus_summary_loop         = [];
        my $deleted_locus_summary_loop = [];
        my $i                          = 0;
        my @locus_ids                  = sort { $a <=> $b } keys %all_loci;
        for my $locus_id (@locus_ids) {
            $i++;
            my $summary_row = {};

            $summary_row->{locus_id}   = $locus_id;
            $summary_row->{gene_locus} = $anno_ref->{loci}->{$locus_id}->{gene_locus};
            $summary_row->{orig_func_annotation} =
              $anno_ref->{loci}->{$locus_id}->{orig_func_annotation};
            $summary_row->{gene_symbol}     = $anno_ref->{loci}->{$locus_id}->{gene_symbol};
            $summary_row->{func_annotation} = $anno_ref->{loci}->{$locus_id}->{func_annotation};
            $summary_row->{comment}         = $anno_ref->{loci}->{$locus_id}->{comment};
            $summary_row->{tableRowClass}   = "info"
              if (  defined $anno_ref->{is_admin}
                and defined $anno_ref->{loci}->{$locus_id}->{is_edit});
            $summary_row->{unapproved} = 1 if (defined $unapproved_loci{$locus_id});

            if (defined $deleted_loci{$locus_id}) {
                push(@$deleted_locus_summary_loop, $summary_row);
            } else {
                push(@$locus_summary_loop, $summary_row);
            }
        }

        $body_tmpl->param(
            loci                       => 1,
            locus_summary_loop         => $locus_summary_loop,
            deleted_locus_summary_loop => $deleted_locus_summary_loop,
            family_id                  => $anno_ref->{family_id},
            user_id                    => $anno_ref->{user_id}
        );

        $page_vars->{page_header} =
            'Community Annotation for <em>'
          . $anno_ref->{family}->{$family_id}->{family_name}
          . '</em> Gene Family';
    } elsif ($feature eq "mutants") {
        $user_id = $anno_ref->{user_id};

        $username =
          (defined $anno_ref->{is_admin})
          ? "admin"
          : $anno_ref->{users}->{$user_id}->{username};

        my $mutant_class_id = $cgi->param('mutant_class_id');

        my %pick_edits = ();
        ($anno_ref, $pick_edits{mutant_class}) = get_feat_info(
            {
                table           => 'mutant_class',
                mutant_class_id => $mutant_class_id,
                user_id         => $user_id,
                anno_ref        => $anno_ref,
            }
        );

        my ($mutant_class_sym, $mutant_class_name) = (
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
        );

        $title = 'Annotate ' . $mutant_class_sym . ' Mutant Class';
        my %mutant_ids = selectall_id(
            {
                table   => 'mutant_info',
                where   => { mutant_class_id => $mutant_class_id },
                user_id => $user_id
            }
        );

        my %deleted_mutant_info    = ();
        my %unapproved_mutant_info = ();
        foreach my $mutant_id (sort { $a <=> $b } keys %mutant_ids) {
            (
                $anno_ref,
                $pick_edits{mutant_info},
                $unapproved_mutant_info{$mutant_id},
                $deleted_mutant_info{$mutant_id}
              )
              = get_feat_info(
                {
                    table       => 'mutant_info',
                    mutant_id   => $mutant_id,
                    user_id     => $user_id,
                    anno_ref    => $anno_ref,
                    extra_flags => 1
                }
              );

            $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles} = count_features(
                { table => 'alleles', where => { mutant_id => $mutant_id }, user_id => $user_id });
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        my $m                           = 0;
        my $mutant_summary_loop         = [];
        my $deleted_mutant_summary_loop = [];
        my @mutant_ids                  = sort { $a <=> $b } keys %mutant_ids;
        for my $mutant_id (@mutant_ids) {
            next
              unless (
                $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id} == $mutant_class_id);

            my $row = {};

            $row->{mutant_id}     = $mutant_id;
            $row->{mutant_symbol} = $anno_ref->{mutant_info}->{$mutant_id}->{symbol};
            $row->{phenotype}     = $anno_ref->{mutant_info}->{$mutant_id}->{phenotype};
            $row->{num_alleles}   = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};
            $row->{mapping_data}  = $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data};
            $row->{reference_lab} = $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab};
            $row->{reference_pub} = join ";<br />",
              (split /;/, $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub});
            $row->{tableRowClass} = "tableRowEven";
            $row->{unapproved} = 1 if (defined $unapproved_mutant_info{$mutant_id});

=commemt
            if ($m == 0) {
                $row->{mutant_class}      = 1;
                $row->{mutant_class_sym}  = $mutant_class_sym;
                $row->{mutant_class_name} = $mutant_class_name;
                $row->{num_mutants}       = scalar @mutant_ids;
            }
=cut

            $m++;

            if (defined $deleted_mutant_info{$mutant_id}) {
                push(@$deleted_mutant_summary_loop, $row);
            } else {
                push(@$mutant_summary_loop, $row);
            }

            #push @$mutant_summary_loop, $row;
        }

        $body_tmpl->param(
            mutants                     => 1,
            user_id                     => $user_id,
            mutant_class_id             => $mutant_class_id,
            mutant_class_name           => $mutant_class_name,
            mutant_summary_loop         => $mutant_summary_loop,
            deleted_mutant_summary_loop => $deleted_mutant_summary_loop,
        );

        $page_vars->{page_header} =
          'Community Annotation for <em>' . $mutant_class_sym . '</em> Mutant Class';
    }
    print $session->header;

    #print $body_tmpl->output;
    push @{ $page_vars->{javascripts} }, "/eucap/include/js/annotate.js",
      "/eucap/include/js/jquery.qtip.min.js",
      "/eucap/include/js/jquery.tagsinput.js",
      "/eucap/include/js/jquery.selectBox.min.js",
      "/eucap/include/js/textpresso.js";

    push @{ $page_vars->{stylesheets} }, "/eucap/include/css/jquery.qtip.css",
      "/eucap/include/css/jquery.tagsinput.css",
      "/eucap/include/css/jquery.selectBox.css",
      "/eucap/include/css/navigation.css";

    push @{ $page_vars->{breadcrumb} },
      (
        {
            'link'      => '/cgi-bin/eucap/eucap.pl?action=dashboard',
            'menu_name' => 'Dashboard'
        },
        { 'link' => $ENV{REQUEST_URI}, 'menu_name' => $title }
      );
    $page_vars->{title} = "EuCAP :: $title";

    my $panel_select = ($feature eq "mutants") ? "&mutant_panel=1" : "";
    $page_vars->{is_family_editor} = 1 if (defined $anno_ref->{is_family_editor});
    $page_vars->{user_info} = {
        'username'     => $username,
        'name'         => $anno_ref->{users}->{$user_id}->{name},
        'organization' => $anno_ref->{users}->{$user_id}->{organization},
        'email'        => $anno_ref->{users}->{$user_id}->{email},
        'url'          => $anno_ref->{users}->{$user_id}->{url},
        'email_hash'   => md5_hex($anno_ref->{users}->{$user_id}->{email}),
    };
    $page_vars->{main_content} = $body_tmpl->output;
}

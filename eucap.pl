#!/usr/local/bin/perl

use warnings;
use strict;
use feature qw( state );

# Set the perl5lib path variable
BEGIN {
    unshift @INC, '../', './lib', './lib/5.10.1';
}

# CGI and authentication related modules
use CGI;
use CGI::Carp qw( fatalsToBrowser );
use CGI::Session;
use Digest;
use Authen::Passphrase::MD5Crypt;

# Page rendering Template modules
use Template;
use HTML::Template;
use Print_to_screen;

# Data related modules
use URI;
use JSON;
use Switch;
use IO::String;
use Image::Size;
use File::Copy;
use File::Temp;
use File::Basename;
use Data::Dumper;
use Time::Piece;

#Bioperl classes
use Bio::SeqIO;
use Bio::SearchIO;

#use Bio::DB::GFF;
use Bio::DB::SeqFeature::Store;
use Bio::SeqFeature::Generic;
use Bio::Graphics;
use Bio::Graphics::Feature;

# DB related modules
use DBI;

# Class::DBI ORM Helper Classes
use CA::DBHelper;
use CA::API;

# Third-party modules
use MIME::Base64 qw/encode_base64url/;
use Data::Difference qw/data_diff/;

my @breadcrumb  = ();
my @stylesheets = ();
my @javascripts = ();

my $email_domain  = "\@jcvi.org";
my $PA            = "sbidwell";
my $admin         = "vkrishnakumar";
my $PA_address    = $PA . $email_domain;
my $admin_address = $admin . $email_domain;
my $title         = "";

my $jcvi_vars = {};
my $FLAG      = 0;

#webserver path params
my $APACHE_DOC_ROOT    = $ENV{"DOCUMENT_ROOT"};
my $WEBSERVER_DOC_PATH = $APACHE_DOC_ROOT . "/medicago";
my $WEBSERVER_TEMP_REL = '/medicago/tmp';

# Allow max 1MB upload size
$CGI::POST_MAX = 1024 * 1000;

# Describe safe file name characters (no spaces or symbols allowed
my $safe_filename_characters = "a-zA-Z0-9_.-";

# User profile image upload path
my $CA_USER_IMAGE_PATH = $WEBSERVER_DOC_PATH . "/eucap/include/images/ca_users";

#Config
my $PROTEOME_BLAST_DB =
  $WEBSERVER_DOC_PATH . '/eucap/blast_dbs/Mt3.5v5_GenesProteinSeq_20111014.fa';
my $WEBSERVER_TEMP_DIR = $WEBSERVER_DOC_PATH . '/tmp';
my $BLASTALL           = '/usr/local/bin/blastall';

#local GFF DB connection params
my $GFF_DB_ADAPTOR  = 'DBI::mysql';                                         #Bio DB SeqFeature Store
my $GFF_DB_HOST     = 'mysql51-dmz-pro';
my $GFF_DB_NAME     = 'medtr_gbrowse2';
my $GFF_DB_DSN      = join(':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST));
my $GFF_DB_USERNAME = 'access';
my $GFF_DB_PASSWORD = 'access';

#need this db connection for base annotation data
my $gff_dbh = Bio::DB::SeqFeature::Store->new(
    -adaptor => $GFF_DB_ADAPTOR,
    -dsn     => $GFF_DB_DSN,
    -user    => $GFF_DB_USERNAME,
    -pass    => $GFF_DB_PASSWORD,
) or die("cannot access Bio::DB::SeqFeature::Store database");

#local community annotation DB connection params
my $CA_DB_NAME = 'MTGCommunityAnnot';
my ($CA_DB_USERNAME, $CA_DB_PASSWORD, $CA_DB_HOST);
switch ($ENV{'WEBTIER'}) {
    case /dev/ {
        ($CA_DB_USERNAME, $CA_DB_PASSWORD, $CA_DB_HOST) = ('vkrishna', 'L0g!n2db', 'mysql-lan-pro');
    }
    else {
        ($CA_DB_USERNAME, $CA_DB_PASSWORD, $CA_DB_HOST) =
          ('eucap', 'Zs5Nud6mDuhEVzKC', 'mysql-dmz-pro');
    }
}
my $CA_DB_DSN = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));

# actions that do not require session validation (no login necessary)
my %actions_nologin = (
    "check_username"    => 1,
    "check_email"       => 1,
    "get_loci"          => 1,
    "get_mutant_info"   => 1,
    "signup_page"       => 1,
    "signup_user"       => 1,
    "validate_new_user" => 1
);

# need this dbh for CGI::Session
my $ca_dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD)
  or die("cannot connect to CA database:$!");

my $cgi      = CGI->new;
my $action   = $cgi->param('action');
my $locus_id = $cgi->param('locus_id');

my $session;
if (not defined $actions_nologin{$action}) {
    CGI::Session->name("EuCAP_ID");
    $session = CGI::Session->new("driver:mysql", $cgi, { Handle => $ca_dbh })
      or die(CGI::Session->errstr . "\n");

    init($session, $cgi);
    $session->flush;

    unless ($session->param('~logged_in')) {
        login_page();
    }
}

if ($action eq 'signup_page') {
    signup_page($cgi);
}
elsif ($action eq 'signup_user') {
    signup_user($cgi);
    $FLAG = 1;
}
elsif ($action eq 'validate_new_user') {
    validate_new_user($cgi);
}
elsif ($action eq 'dashboard') {
    dashboard($session, $cgi);
}
elsif ($action eq 'edit_profile') {
    edit_profile($session, $cgi);
}
elsif ($action eq 'update_profile') {
    edit_profile($session, $cgi, 1);
    $FLAG = 1;
}

# Locus/mutant specific actions
elsif ($action eq 'annotate') {
    annotate($session, $cgi, 'loci');
}
elsif ($action eq 'annotate_locus') {
    annotate_locus($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'save_locus') {
    annotate_locus($session, $cgi, 1);
    $FLAG = 1;
}
elsif ($action eq 'add_loci') {
    add_loci($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'get_loci') {
    my $gene_locus = $cgi->param('term');
    my $limit = (defined $cgi->param('limit')) ? $cgi->param('limit') : 10;

    get_loci({ cgi => $cgi, gene_locus => $gene_locus, limit => $limit });
    $FLAG = 1;
}
elsif ($action eq 'delete_locus') {
    delete_locus($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'undelete_locus') {
    undelete_locus($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'run_blast') {
    run_blast($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'get_mutant_info') {
    my $mutant_sym = $cgi->param('term');
    my $limit      = (defined $cgi->param('limit')) ? $cgi->param('limit') : 10;
    my $edits      = (defined $cgi->param('edits')) ? $cgi->param('edits') : undef;

    get_mutant_info({ cgi => $cgi, symbol => $mutant_sym, limit => $limit, edits => $edits });
    $FLAG = 1;
}

# Mutant-specific actions
elsif ($action eq 'annotate_mutants') {
    annotate($session, $cgi, 'mutants');
}
elsif ($action eq 'annotate_mutant') {
    annotate_mutant($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'save_mutant') {
    annotate_mutant($session, $cgi, 1);
    $FLAG = 1;
}

# Allele-specific actions
elsif ($action eq 'annotate_alleles') {
    annotate_alleles($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'save_alleles') {
    annotate_alleles($session, $cgi, 1);
    $FLAG = 1;
}
elsif ($action eq 'add_alleles') {
    add_alleles($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'delete_allele') {
    delete_allele($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'undelete_allele') {
    undelete_allele($session, $cgi);
    $FLAG = 1;
}

# Structural annotation specific actions
elsif ($action eq 'struct_anno') {
    structural_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'submit_struct_anno') {
    submit_structural_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'review_annotation') {
    review_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'submit_annotation') {
    submit_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'final_submit') {
    final_submit($session, $cgi);
}
elsif ($action eq 'check_username') {
    my $username = $cgi->param('username');
    my $user_id  = (defined $cgi->param('user_id')) ? $cgi->param('user_id') : undef;
    my $ignore   = (defined $cgi->param('ignore')) ? $cgi->param('ignore') : undef;

    check_username($username, $user_id, $ignore);
    $FLAG = 1;
}
elsif ($action eq 'check_email') {
    my $email = $cgi->param('email');
    my $ignore = (defined $cgi->param('ignore')) ? $cgi->param('ignore') : undef;

    check_email($email, $ignore);
    $FLAG = 1;
}
elsif ($action eq 'logout') {
    logout($session, $cgi);
}
else {    # logged in and fall through the actions - then log out
    logout($session, $cgi, 'Sorry! System error. Please report issue to site administrator.');
}

# $FLAG == 0 corresponds to any option resulting in a complete page reload
# $FLAG == 1 corresponds to an asynchronous requests returing JSON/HTML/PLAINTEXT
PROCESS_TMPL: if (!$FLAG) {
    output_to_jcvi_tmpl($jcvi_vars);
}

$ca_dbh->disconnect if $ca_dbh;

# EuCAP subroutines
sub init {
    my ($session, $cgi) = @_;
    if ($session->param('~logged_in')) {
        return 1;
    }
    unless ($cgi->param('action')) {
        login_page(undef);
        goto PROCESS_TMPL;
    }

    my $username = $cgi->param('username');
    my $password = $cgi->param('password');
    my $user     = selectrow({ table => 'users', where => { username => $username } });
    if (!$user) {
        login_page(1, "User name not found. Please check and try again.");
        goto PROCESS_TMPL;
    }

    my $salt      = $user->salt;
    my $hash      = $user->hash;
    my $crypt_obj = Authen::Passphrase::MD5Crypt->new(salt => $salt, hash_base64 => $hash);
    if ($crypt_obj->match($password)) {

        #authenticated
        $session->param('~logged_in', 1);

        #store user_id as a CGI::session param
        my $anno_ref = {};
        $anno_ref->{user_id} = $user->user_id;
        $anno_ref->{is_admin} = 1 if ($username eq "admin");

        $session->param('anno_ref', $anno_ref);
        $session->flush;
        return 1;
    }
    else {
        login_page(1, "Password does not match! Please check and try again.");
        goto PROCESS_TMPL;
    }
}

sub login_page {
    my ($is_err_msgor, $error_string) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/login.tmpl");
    if ($is_err_msgor) {
        $tmpl->param(error        => 1);
        $tmpl->param(error_string => $error_string);
    }
    print $cgi->header;

    my $title = "Community Annotation Portal";
    push @{ $jcvi_vars->{breadcrumb} }, ({ 'link' => '#', 'menu_name' => $title });

    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl',
            'menu_name' => 'EuCAP Home'
        },
    ];
    $jcvi_vars->{title}       = "Medicago truncatula Genome Project :: EuCAP :: $title";
    $jcvi_vars->{page_header} = $title;

    $jcvi_vars->{main_content} = $tmpl->output;
}

sub signup_page {
    my ($cgi) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/signup_page.tmpl");

    print $cgi->header(-type => 'text/html');
    my $title = "Account Sign Up";

    push @{ $jcvi_vars->{javascripts} }, "/medicago/eucap/include/js/jquery.validate.min.js",
      "/medicago/eucap/include/js/jquery.form.js", "/medicago/eucap/include/js/signup_page.js";
    push @{ $jcvi_vars->{breadcrumb} }, { 'link' => '#', 'menu_name' => $title };

    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl',
            'menu_name' => 'EuCAP Home'
        },
    ];
    $jcvi_vars->{title}       = "Medicago truncatula Genome Project :: EuCAP :: $title";
    $jcvi_vars->{page_header} = "EuCAP Account Sign Up";

    $jcvi_vars->{main_content} = $tmpl->output;
}

sub signup_user {
    my ($cgi) = @_;

    my $user_info = cgi_to_hashref({ cgi => $cgi, table => 'users', id => undef });

    my $crypt_obj =
      Authen::Passphrase::MD5Crypt->new(salt_random => 1, passphrase => $user_info->{password})
      or die;
    $user_info->{salt} = $crypt_obj->salt;
    $user_info->{hash} = $crypt_obj->hash_base64;

    eval {
        $user_info->{validation_key} = validation_hash($user_info);
        my $pending_user_row = do('insert', 'registration_pending', $user_info);
    };

    if ($@) {
        die "Registration Error. Please notify site administrator: $@\n\n";
    }

    my $tmpl = HTML::Template->new(filename => "./tmpl/email_body_new.tmpl");
    my $validation_url = URI->new(join "", 'http://', $ENV{'HTTP_HOST'}, $ENV{'SCRIPT_NAME'});
    $validation_url->query_form(
        'action'         => 'validate_new_user',
        'username'       => $user_info->{username},
        'validation_key' => $user_info->{validation_key}
    );
    $tmpl->param(validation_url => $validation_url);
    my $email_body = $tmpl->output;

    my $success = send_email(
        {
            to_addr  => $user_info->{email},
            bcc_addr => $admin_address,
            subject  => '[EuCAP] New User Registration',
            body     => $email_body
        }
    );

    print $cgi->header(-type => 'text/plain');
    ($success)
      ? print 'Success! Please check your email for confirmation.'
      : print 'Error: Please notify website administrator';
}

sub validate_new_user {
    my ($cgi) = @_;

    my $validate_info =
      cgi_to_hashref({ cgi => $cgi, table => 'registration_pending', id => undef });
    my $pending_user = selectrow(
        {
            table => 'registration_pending',
            where => { username => $validate_info->{username} }
        }
    );
    if (defined $pending_user
        and $pending_user->validation_key eq $validate_info->{validation_key})
    {
        promote_pending_user($pending_user);
        login_page(1, 'Account activated successfully');
    }
    else {
        login_page(1,
                "Bad validation using username="
              . $cgi->param('username')
              . "and validation_key="
              . $cgi->param('validation_key'));
    }
    goto PROCESS_TMPL;
}

sub logout {
    my ($session, $cgi) = @_;
    $session->clear(["~logged_in"]);
    $session->flush;
    login_page(1, "Logged out - Thank you");
}

sub dashboard {
    my ($session, $cgi) = @_;
    my $title    = "Annotator Dashboard";
    my $tmpl     = HTML::Template->new(filename => "./tmpl/dashboard.tmpl");
    my $anno_ref = $session->param('anno_ref');

    my $user_id = (defined $anno_ref->{is_admin}) ? 0 : $anno_ref->{user_id};
    $anno_ref = get_info({ table => 'users', id => $user_id, anno_ref => $anno_ref, session => $session });
    my $username = $anno_ref->{users}->{$user_id}->{username};

    my @fams =
      ($username eq "admin")
      ? selectall_array('family')
      : selectall_array('family', { user_id => $anno_ref->{user_id} });

    my $disabled         = undef;
    my $gene_family_list = [];
    if (scalar @fams == 0) {
        $disabled = 1;
    }
    else {
        foreach my $fam (@fams) {
            my $family_id = $fam->family_id;

            my $edits = 0;
            if (defined $anno_ref->{is_admin}) {
                my @loci_edits_objs = selectall_array('loci_edits', { family_id => $family_id });
                $edits = scalar @loci_edits_objs;
            }

            my $row = {
                user_id           => $fam->user_id,
                family_id         => $family_id,
                gene_class_symbol => $fam->gene_class_symbol,
                family_name       => $fam->family_name,
                description       => (defined $anno_ref->{is_admin}) ? $edits : $fam->description
            };
            push @$gene_family_list, $row;

            if (not defined $anno_ref->{is_admin}) {
                $anno_ref->{family_id}                                 = $family_id;
                $anno_ref->{family}->{$family_id}->{family_name}       = $fam->family_name;
                $anno_ref->{family}->{$family_id}->{gene_class_symbol} = $fam->gene_class_symbol;
                $anno_ref->{family}->{$family_id}->{description}       = $fam->description;
            }
        }
        $tmpl->param(gene_family_radio => $gene_family_list,);
    }

    my $mutant_class_list = [];
    my $mutant_class_objs = selectall_iter('mutant_class');
    while (my $mutant_class_obj = $mutant_class_objs->next) {
        my $mutant_class_id = $mutant_class_obj->mutant_class_id;
        my ($mutant_class_sym, $mutant_class_name) =
          ($mutant_class_obj->symbol, $mutant_class_obj->symbol_name);

        my @mutant_info_objs = selectall_array(
            'mutant_info',
            { mutant_class_id => $mutant_class_id },
            { order_by        => 'mutant_id' }
        );

        my $row = {
            mutant_class_id     => $mutant_class_id,
            mutant_class_symbol => $mutant_class_sym,
            mutant_class_name   => $mutant_class_name,
            num_mutants         => scalar @mutant_info_objs,
            user_id             => $user_id,
        };

        push @$mutant_class_list, $row;
    }

    $tmpl->param(
        mutant_class_list => $mutant_class_list,
        image_name        => $anno_ref->{users}->{$user_id}->{photo_file_name},
        name              => $anno_ref->{users}->{$user_id}->{name},
        organization      => $anno_ref->{users}->{$user_id}->{organization},
        email             => $anno_ref->{users}->{$user_id}->{email},
        url               => $anno_ref->{users}->{$user_id}->{url},
        disabled          => $disabled,
    );

    if (defined $anno_ref->{is_admin}) {
        $tmpl->param(is_admin => 1);
        undef $anno_ref->{user_id};
        undef $anno_ref->{users};
        undef $anno_ref->{family_id};
        undef $anno_ref->{family};
        delete $anno_ref->{loci};
        delete $anno_ref->{mutant_info};
        delete $anno_ref->{mutant_class};
        delete $anno_ref->{alleles};
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header;

    push @{ $jcvi_vars->{breadcrumb} }, ({ 'link' => '#', 'menu_name' => $title });
    $jcvi_vars->{title}       = "Medicago truncatula Genome Project :: EuCAP :: $title";
    $jcvi_vars->{page_header} = "Annotator Dashboard";
    $jcvi_vars->{top_menu}    = [
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub edit_profile {
    my ($session, $cgi, $save) = @_;
    my $title    = "Edit User Profile";
    my $anno_ref = $session->param('anno_ref');

    my $user_id = (defined $anno_ref->{is_admin}) ? 0 : $anno_ref->{user_id};
    $anno_ref = get_info({ table => 'users', id => $user_id, anno_ref => $anno_ref, session => $session });
    my $username      = $anno_ref->{users}->{$user_id}->{username};
    my $update_status = "";

    if ($save) {
        my $user_id          = $cgi->param('user_id');
        my $new_username     = $cgi->param('username');
        my $new_name         = $cgi->param('name');
        my $new_organization = $cgi->param('organization');
        my $new_email        = $cgi->param('email');
        my $new_url          = $cgi->param('url');

        my $new_photo   = $cgi->param('photo');
        my %photo_valid = (
            extension  => 1,
            file_size  => 1,
            dimensions => 1
        );
        my $photoUploaded;
        my %result = ();

        my $new_photo_file_name;
        if ($new_photo) {
            my @suffixes = (".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG");
            my ($name, $path, $extension) = fileparse($new_photo, @suffixes);
            $new_photo = $name . $extension;

            $new_photo =~ tr/ /_/;
            $new_photo =~ s/[^$safe_filename_characters]//g;

            if (    $new_photo =~ /^([$safe_filename_characters]+)$/
                and $extension =~ /\.[jpg|jpeg|png]/i)
            {
                $new_photo_file_name = $new_username . $extension;

                my $upload_filehandle = $cgi->upload("photo");
                eval {
                    open UPLOADFILE, ">", "$WEBSERVER_TEMP_DIR/$new_photo_file_name"
                      or die "$!";
                    binmode UPLOADFILE;
                    while (<$upload_filehandle>) {
                        print UPLOADFILE $_;
                    }
                    close UPLOADFILE;
                };

                if ($@) {
                    $photo_valid{file_size} = undef;
                }

                my ($width, $height) = imgsize("$WEBSERVER_TEMP_DIR/$new_photo_file_name");
                if ($width <= 200 and $height <= 200) {
                    File::Copy::move(
                        "$WEBSERVER_TEMP_DIR/$new_photo_file_name",
                        "$CA_USER_IMAGE_PATH/$new_photo_file_name"
                    ) or die "$!";

                    $photoUploaded = 1;
                }
                else {
                    $photo_valid{dimensions} = undef;
                }
            }
            else {
                $photo_valid{extension} = undef;
            }
        }

        $anno_ref->{users}->{$user_id}->{username}        = $new_username;
        $anno_ref->{users}->{$user_id}->{name}            = $new_name;
        $anno_ref->{users}->{$user_id}->{organization}    = $new_organization;
        $anno_ref->{users}->{$user_id}->{email}           = $new_email;
        $anno_ref->{users}->{$user_id}->{url}             = $new_url;
        $anno_ref->{users}->{$user_id}->{photo_file_name} = $new_photo_file_name
          if (defined $photoUploaded);

        if (    defined $photo_valid{dimensions}
            and defined $photo_valid{file_size}
            and defined $photo_valid{extension})
        {
            update_user_info($user_id, $anno_ref);
            $update_status           = 'Profile updated!';
            $result{photo_file_name} = $anno_ref->{users}->{$user_id}->{photo_file_name};
            $result{error}           = undef;
        }
        else {
            $update_status = "Error: Please check ";
            $update_status .= (not defined $photo_valid{extension})  ? "(file format)" : "";
            $update_status .= (not defined $photo_valid{dimensions}) ? "(dimensions)"  : "";
            $update_status .= (not defined $photo_valid{file_size})  ? "(file size)"   : "";
            $update_status .= " of uploaded picture";

            $result{photo_file_name} = undef;
            $result{error}           = 1;
        }

        $result{update_status} = $update_status;

        print $session->header(-type => 'application/json');
        print JSON::to_json(\%result);
    }
    else {
        my $tmpl = HTML::Template->new(filename => "./tmpl/edit_profile.tmpl");
        $tmpl->param(
            user_id         => $user_id,
            username        => $anno_ref->{users}->{$user_id}->{username},
            name            => $anno_ref->{users}->{$user_id}->{name},
            organization    => $anno_ref->{users}->{$user_id}->{organization},
            email           => $anno_ref->{users}->{$user_id}->{email},
            url             => $anno_ref->{users}->{$user_id}->{url},
            photo_file_name => $anno_ref->{users}->{$user_id}->{photo_file_name},
        );
        print $session->header;

        push @{ $jcvi_vars->{javascripts} }, "/medicago/eucap/include/js/jquery.validate.min.js",
          "/medicago/eucap/include/js/jquery.form.js",
          "/medicago/eucap/include/js/edit_profile.js";
        push @{ $jcvi_vars->{breadcrumb} },
          (
            {
                'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=dashboard',
                'menu_name' => 'Dashboard'
            },
            { 'link' => '#', 'menu_name' => $title }
          );
        $jcvi_vars->{title}    = "Medicago truncatula Genome Project :: EuCAP :: $title";
        $jcvi_vars->{top_menu} = [
            {
                'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=dashboard',
                'menu_name' => 'Dashboard'
            },
            {
                'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=logout',
                'menu_name' => 'Logout (<em>'
                  . $anno_ref->{users}->{$user_id}->{username}
                  . '</em>)'
            }
        ];
        $jcvi_vars->{main_content} = $tmpl->output;
    }
}

sub annotate {
    my ($session, $cgi, $feature) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/annotate.tmpl");
    my $anno_ref = $session->param('anno_ref');

    my $username = "";
    if ($feature eq 'loci') {
        my ($user_id, $family_id) = ($cgi->param('user_id'), $cgi->param('family_id'));
        if (defined $anno_ref->{is_admin}) {
            $anno_ref = get_info({ table => 'users', id => $user_id, anno_ref => $anno_ref, session => $session });
            $anno_ref = get_info({ table => 'family', id => $family_id, anno_ref => $anno_ref, session => $session });
        }

        $username =
          (defined $anno_ref->{is_admin}) ? "admin" : $anno_ref->{users}->{$user_id}->{username};

        $title =
          'Annotate ' . $anno_ref->{family}->{$family_id}->{gene_class_symbol} . ' Gene Family';

        # coming in from the select family action - the database is the most up to data source
        # count the number of loci for this family (uniq of all loci in the original & edits table
        my %all_loci =
          selectall_id('loci',
            { family_id => $anno_ref->{family_id}, user_id => $anno_ref->{user_id} });

        # loop through each locus_id and investigate associated mutants/alleles
        my %deleted_loci = ();
        foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
            my %pick_edits = ();

            my $locus_edits_hashref = {};
            $locus_edits_hashref =
              selectrow_hashref({ table => 'loci_edits', primary_key => $locus_id, edits => 1 });

            my $locus_hashref = {};
            $locus_hashref = selectrow_hashref({ table => 'loci', primary_key => $locus_id });

            if ($locus_edits_hashref->{is_deleted}) {
                $deleted_loci{$locus_id} = 1;
                $anno_ref->{loci}->{$locus_id} =
                  (scalar keys %{$locus_edits_hashref} > 1) ? $locus_edits_hashref : $locus_hashref;
                next;
            }

            ($locus_edits_hashref, $pick_edits{loci}) = cmp_hashref(
                {
                    orig     => $locus_hashref,
                    edits    => $locus_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            ($locus_edits_hashref->{is_edit}, $anno_ref->{loci}->{$locus_id}) =
              ($pick_edits{loci}) ? (1, $locus_edits_hashref) : (undef, $locus_hashref);

            if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
                and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
            {
                my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

                my $mutant_edits_hashref = {};
                $mutant_edits_hashref = selectrow_hashref(
                    {
                        table       => 'mutant_info_edits',
                        primary_key => $mutant_id,
                        edits       => 1
                    }
                );

                my $mutant_hashref = {};
                $mutant_hashref =
                  selectrow_hashref({ table => 'mutant_info', primary_key => $mutant_id });

                ($mutant_edits_hashref, $pick_edits{mutant_info}) = cmp_hashref(
                    {
                        orig     => $mutant_hashref,
                        edits    => $mutant_edits_hashref,
                        is_admin => $anno_ref->{is_admin}
                    }
                );
                ($mutant_edits_hashref->{is_edit}, $anno_ref->{mutant_info}->{$mutant_id}) =
                    ($pick_edits{mutant_info})
                  ? (1, $mutant_edits_hashref)
                  : (undef, $mutant_hashref);

                # count the number of alleles for the above mutant
                # both from the original & edits tables
                my %all_alleles = selectall_id('alleles', { mutant_id => $mutant_id });
                $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles} = scalar keys %all_alleles;

                my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

                my $mutant_class_edits_hashref = {};
                $mutant_class_edits_hashref = selectrow_hashref(
                    {
                        table       => 'mutant_class_edits',
                        primary_key => $mutant_class_id,
                        edits       => 1
                    }
                );

                my $mutant_class_hashref = {};
                $mutant_class_hashref = selectrow_hashref(
                    {
                        table       => 'mutant_class',
                        primary_key => $mutant_class_id,
                    }
                );

                ($mutant_class_edits_hashref, $pick_edits{mutant_class}) = cmp_hashref(
                    {
                        orig     => $mutant_class_hashref,
                        edits    => $mutant_class_edits_hashref,
                        is_admin => $anno_ref->{is_admin}
                    }
                );

                (
                    $mutant_class_edits_hashref->{is_edit},
                    $anno_ref->{mutant_class}->{$mutant_class_id}
                  )
                  =
                    ($pick_edits{mutant_class})
                  ? (1, $mutant_class_edits_hashref)
                  : (undef, $mutant_class_hashref);
            }
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        #now output the session
        my $annotation_summary_loop         = [];
        my $deleted_annotation_summary_loop = [];
        my $i                               = 0;
        my @locus_ids                       = sort { $a <=> $b } keys %{ $anno_ref->{loci} };
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
            $summary_row->{tableRowClass}   = ($i % 2 == 0) ? "tableRowEven" : "tableRowOdd";
            $summary_row->{tableRowClass}   = "tableRowEdit"
              if (  defined $anno_ref->{is_admin}
                and defined $anno_ref->{loci}->{$locus_id}->{is_edit});

            if (defined $deleted_loci{$locus_id}) {
                push(@$deleted_annotation_summary_loop, $summary_row);
            }
            else {
                push(@$annotation_summary_loop, $summary_row);
            }
        }

        $tmpl->param(
            loci                            => 1,
            annotation_summary_loop         => $annotation_summary_loop,
            deleted_annotation_summary_loop => $deleted_annotation_summary_loop,
            family_id                       => $anno_ref->{family_id}
        );

        $jcvi_vars->{page_header} =
            'Community Annotation for '
          . $anno_ref->{family}->{$family_id}->{family_name}
          . ' Gene Family';
    }
    elsif ($feature eq "mutants") {
        my $user_id = $cgi->param('user_id');

        if (defined $anno_ref->{is_admin}) {
            $anno_ref = get_info({ table => 'users', id => $user_id, anno_ref => $anno_ref, session => $session });
        }

        $username =
          (defined $anno_ref->{is_admin}) ? "admin" : $anno_ref->{users}->{$user_id}->{username};

        my $mutant_class_id = $cgi->param('mutant_class_id');

        my %pick_edits = ();

        my $mutant_class_edits_hashref = {};
        $mutant_class_edits_hashref = selectrow_hashref(
            {
                table       => 'mutant_class_edits',
                primary_key => $mutant_class_id,
                edits       => 1
            }
        );

        my $mutant_class_hashref = {};
        $mutant_class_hashref = selectrow_hashref(
            {
                table       => 'mutant_class',
                primary_key => $mutant_class_id,
            }
        );

        ($mutant_class_edits_hashref, $pick_edits{mutant_class}) = cmp_hashref(
            {
                orig     => $mutant_class_hashref,
                edits    => $mutant_class_edits_hashref,
                is_admin => $anno_ref->{is_admin}
            }
        );

        ($mutant_class_edits_hashref->{is_edit}, $anno_ref->{mutant_class}->{$mutant_class_id}) =
            ($pick_edits{mutant_class})
          ? (1, $mutant_class_edits_hashref)
          : (undef, $mutant_class_hashref);

        my ($mutant_class_sym, $mutant_class_name) = (
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
            $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
        );

        $title = 'Annotate ' . $mutant_class_sym . ' Mutant Class';
        my %mutant_ids = selectall_id('mutant_info', { mutant_class_id => $mutant_class_id });

        foreach my $mutant_id (sort { $a <=> $b } keys %mutant_ids) {
            my $mutant_edits_hashref = {};
            $mutant_edits_hashref = selectrow_hashref(
                {
                    table       => 'mutant_info_edits',
                    primary_key => $mutant_id,
                    edits       => 1
                }
            );

            my $mutant_hashref = {};
            $mutant_hashref =
              selectrow_hashref({ table => 'mutant_info', primary_key => $mutant_id });

            ($mutant_edits_hashref, $pick_edits{mutant_info}) = cmp_hashref(
                {
                    orig     => $mutant_hashref,
                    edits    => $mutant_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );
            ($mutant_edits_hashref->{is_edit}, $anno_ref->{mutant_info}->{$mutant_id}) =
                ($pick_edits{mutant_info})
              ? (1, $mutant_edits_hashref)
              : (undef, $mutant_hashref);

            # count the number of alleles for the above mutant
            # both from the original & edits tables
            my %all_alleles = selectall_id('alleles', { mutant_id => $mutant_id });
            $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles} = scalar keys %all_alleles;
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        my $m                = 0;
        my $mutant_info_loop = [];
        my @mutant_ids       = sort { $a <=> $b } keys %{ $anno_ref->{mutant_info} };
        for my $mutant_id (@mutant_ids) {
            next
              unless (
                $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id} == $mutant_class_id);

            my $row = {};

            $row->{mutant_id}       = $mutant_id;
            $row->{mutant_symbol}   = $anno_ref->{mutant_info}->{$mutant_id}->{symbol};
            $row->{phenotype}       = $anno_ref->{mutant_info}->{$mutant_id}->{phenotype};
            $row->{num_alleles}     = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};
            $row->{mapping_data}    = $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data};
            $row->{reference_lab}   = $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab};
            $row->{table_row_class} = "tableRowEven";

            if ($m == 0) {
                $row->{mutant_class}      = 1;
                $row->{mutant_class_sym}  = $mutant_class_sym;
                $row->{mutant_class_name} = $mutant_class_name;
                $row->{num_mutants}       = scalar @mutant_ids;
            }

            $m++;
            push @$mutant_info_loop, $row;
        }

        $tmpl->param(
            mutants          => 1,
            mutant_info_loop => $mutant_info_loop,
        );

        $jcvi_vars->{page_header} =
          'Community Annotation for ' . $mutant_class_sym . ' Mutant Class';
    }
    print $session->header;

    #print $tmpl->output;
    push @{ $jcvi_vars->{javascripts} }, "/medicago/eucap/include/js/annotate.js",
      "/medicago/include/js/jquery.qtip.min.js";
    push @{ $jcvi_vars->{stylesheets} }, "/medicago/include/css/jquery.qtip.css";
    push @{ $jcvi_vars->{breadcrumb} },
      (
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=dashboard',
            'menu_name' => 'Dashboard'
        },
        { 'link' => '#', 'menu_name' => $title }
      );
    $jcvi_vars->{title}    = "Medicago truncatula Genome Project :: EuCAP :: $title";
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=dashboard',
            'menu_name' => 'Dashboard'
        },
        {
            'link'      => '/cgi-bin/medicago/eucap/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub add_loci {
    my ($session, $cgi) = @_;
    my $loci_list = $cgi->param('loci_list');
    my $anno_ref  = $session->param('anno_ref');

    $loci_list =~ s/\s+//;

    my @new_loci = split /,/, $loci_list;
    my $track    = 0;
    my $locus_id = "";
  LOCUS: for my $gene_locus (@new_loci) {

        #next unless ($gene_locus =~ /^Medtr[1-8]g\d+|^\S+_\d+|^contig_\d+_\d+/);
        next
          unless ($gene_locus =~ /\bMedtr\d{1}g\d+\b/
            or $gene_locus =~ /\b\w{2}\d+_\d+\b/
            or $gene_locus =~ /\bcontig_\d+_\d+\b/);

        my $locus_obj = selectrow({ table => 'loci', where => { gene_locus => $gene_locus } });

        my $new_locus_obj;
        if (defined $locus_obj) {
            $locus_id = $locus_obj->locus_id;

            my $locus_edits_obj = selectrow({ table => 'loci_edits', primary_key => $locus_id });
            if (defined $locus_edits_obj) {
                my $locus_edits_hashref =
                  makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });

                if ($locus_edits_hashref->{is_deleted}) {

                    # If not 'admin' user, allow user to re-add the locus
                    # else, delete the empty edits object, bring back
                    # the original entry and continue processing the
                    # input locus list
                    $locus_edits_obj->delete;
                    goto INSERT if (not defined $anno_ref->{is_admin});
                }
            }
            next LOCUS;
        }
        else {
            my $locus_edits_objs = selectall_iter('loci_edits');
            while (my $locus_edits_obj = $locus_edits_objs->next()) {
                my $locus_edits_hashref =
                  makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });

                if ($locus_edits_hashref->{gene_locus} eq $gene_locus) {
                    if ($locus_edits_hashref->{is_deleted}) {
                        $locus_edits_obj->delete;
                        goto INSERT if (not defined $anno_ref->{is_admin});
                    }
                }
                else {
                    next LOCUS;
                }
            }
        }

        # If not 'admin', get max(locus_id) after checking the 'loci'
        # and 'loci_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $locus_id = max_id({ table => 'loci' });
        }
        else {    # else, insert new 'loci' row, get $locus_id and continue
            $new_locus_obj = do(
                'insert', 'loci',
                {
                    family_id => $anno_ref->{family_id},
                    user_id   => $anno_ref->{user_id}
                }
            );

            $locus_id = $new_locus_obj->locus_id;
        }

      INSERT:
        my $orig_func_annotation = get_original_annotation($gene_locus);

        $anno_ref->{loci}->{$locus_id}->{gene_locus}           = $gene_locus;
        $anno_ref->{loci}->{$locus_id}->{orig_func_annotation} = $orig_func_annotation;
        $anno_ref->{loci}->{$locus_id}->{gene_symbol}          = q{};
        $anno_ref->{loci}->{$locus_id}->{func_annotation}      = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc}       = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc}          = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_protein_acc}       = q{};
        $anno_ref->{loci}->{$locus_id}->{reference_pub}        = q{};
        $anno_ref->{loci}->{$locus_id}->{mod_date}             = timestamp();
        $anno_ref->{loci}->{$locus_id}->{comment}              = q{};
        $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = 0;

        if (not defined $anno_ref->{is_admin}) {
            $anno_ref->{loci}->{$locus_id}->{is_edit} = 1;
            $new_locus_obj = do(
                'insert',
                'loci_edits',
                {
                    locus_id  => $locus_id,
                    user_id   => $anno_ref->{'user_id'},
                    family_id => $anno_ref->{'family_id'},
                    edits     => JSON::to_json($anno_ref->{loci}->{$locus_id})
                }
            );
        }
        else {
            $new_locus_obj->set(
                gene_locus           => $gene_locus,
                orig_func_annotation => $orig_func_annotation,
                gene_symbol          => q{},
                func_annotation      => q{},
                gb_genomic_acc       => q{},
                gb_cdna_acc          => q{},
                gb_protein_acc       => q{},
                reference_pub        => q{},
                mod_date             => $anno_ref->{loci}->{$locus_id}->{mod_date},
                comment              => q{},
                has_structural_annot => 0
            );
        }
        $track++;

        #push @return_vals, JSON::to_json($anno_ref->{loci}->{$locus_id});
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header(-type => 'text/plain');

    #annotate($session, $cgi);
    print $track, ' loc', ($track >= 2 or $track == 0) ? 'i' : 'us', ' added!';
}

sub annotate_locus {
    my ($session, $cgi, $save) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/annotate_locus.tmpl");

    #gene_locus info should already be in the session.
    my $anno_ref = $session->param('anno_ref');
    my $user_id  = $anno_ref->{user_id};
    my $username = $anno_ref->{users}->{$user_id}->{username};

    if ($save) {
        my %result = ();
        my %save_edits =
          ();    # hash to store a flag for each type of feature (loci, mutant_info, mutant_class)
                 # used to track if there are changes or not

# Storing loci is straightforward, there should already be a 'locus_id' for a newly instantiated gene.
        my $locus_hashref = {};
        $locus_hashref =
          selectrow_hashref({ table => 'loci_edits', primary_key => $locus_id, edits => 1 });
        if (scalar keys %{$locus_hashref} == 0) {
            $locus_hashref = selectrow_hashref({ table => 'loci', primary_key => $locus_id });
        }

        my $locus_edits_hashref = cgi_to_hashref({ cgi => $cgi, table => 'loci', id => undef });

        my $e_flag = undef;
        ($locus_edits_hashref, $save_edits{loci}, $e_flag) = cmp_hashref(
            {
                orig     => $locus_hashref,
                edits    => $locus_edits_hashref,
                is_admin => $anno_ref->{is_admin}
            }
        );

        $save_edits{loci} = 1 if (defined $anno_ref->{is_admin} and defined $e_flag);

        $anno_ref->{loci}->{$locus_id} =
          (defined $save_edits{loci}) ? $locus_edits_hashref : $locus_hashref;

        my $params = cgi_to_hashref({ cgi => $cgi, table => 'cgi', id => undef });

# Storing mutant_info - Check if req mutant_info fields have been passed:
# if true: get mutant_id from param or max(mutant_id) + 1 from db or increment if it already exists in the edits table
# else: undef the 'mutant_id' associated with current locus_id (if any) and remove mutant_edits from anno_ref
        my ($mutant_id, $mutant_class_id);
        if (    $params->{'mutant_symbol'} ne ""
            and $params->{'mutant_class_symbol'}  ne ""
            and $params->{'mutant_class_name'}    ne ""
            and $params->{'mutant_phenotype'}     ne ""
            and $params->{'mutant_reference_pub'} ne "")
        {

            $mutant_class_id = $params->{'mutant_class_id'};
            my $mutant_class_hashref = {};
            my $mutant_class_edits_hashref =
              cgi_to_hashref({ cgi => $cgi, table => 'mutant_class', id => undef });

            my $mutant_class_symbol = $params->{'mutant_class_symbol'};

        # if mutant_class_id is not empty, just use the prexisting ID
        # otherwise, check and see if the mutant_class_symbol exists in the DB or not and get its ID
            if ($mutant_class_id eq "") {
                my $mutant_class_obj = selectrow(
                    { table => 'mutant_class', where => { symbol => $mutant_class_symbol } });
                my $mutant_class_edits_obj = selectrow(
                    {
                        table => 'mutant_class_edits',
                        where => { symbol => $mutant_class_symbol }
                    }
                );

                $mutant_class_id =
                  (defined $mutant_class_edits_obj)
                  ? $mutant_class_edits_obj->mutant_class_id
                  : $mutant_class_obj->mutant_class_id;
            }

            if (!$mutant_class_id) {
                $mutant_class_id = max_id({ table => 'mutant_class' });
                $save_edits{mutant_class} = 1;
            }
            else {
                $mutant_class_hashref = selectrow_hashref(
                    { table => 'mutant_class_edits', primary_key => $mutant_class_id });
                if (scalar keys %{$mutant_class_hashref} == 0) {
                    $mutant_class_hashref = selectrow_hashref(
                        { table => 'mutant_class', primary_key => $mutant_class_id });
                }

                $e_flag = undef;
                ($mutant_class_edits_hashref, $save_edits{mutant_class}) = cmp_hashref(
                    {
                        orig     => $mutant_class_hashref,
                        edits    => $mutant_class_edits_hashref,
                        is_admin => $anno_ref->{is_admin}
                    }
                );
                $save_edits{mutant_class} = 1
                  if (defined $anno_ref->{is_admin} and defined $e_flag);
            }

            $anno_ref->{mutant_class}->{$mutant_class_id} =
              ($save_edits{mutant_class})
              ? $mutant_class_edits_hashref
              : $mutant_class_hashref;

            # mutant already exists
            # check to see what has changed between the submission form and the database
            $mutant_id = $params->{'mutant_id'};
            my $mutant_edits_hashref =
              cgi_to_hashref({ cgi => $cgi, table => 'mutant_info', id => undef });
            my $mutant_hashref = {};
            my @alleles        = ();

            my $mutant_symbol = $params->{'mutant_symbol'};

            # if mutant_id is not empty, just use the prexisting ID
            # otherwise, check and see if the mutant_symbol exists in the DB or not and get its ID
            if ($mutant_id eq "") {
                my %mutant_ids =
                  selectall_id('mutant_info', { mutant_class_id => $mutant_class_id });

                foreach my $id (sort { $a <=> $b } keys %mutant_ids) {
                    my $mutant_hashref =
                      selectrow_hashref({ table => 'mutant_info', primary_key => $id });
                    if (scalar keys %{$mutant_hashref} == 0) {
                        $mutant_hashref = selectrow_hashref(
                            { table => 'mutant_info_edits', primary_key => $id, edits => 1 });
                    }

                    if ($mutant_hashref->{mutant_symbol} eq $mutant_symbol) {
                        $mutant_id = $id;
                        last;
                    }
                }
            }

            if (!$mutant_id) {
                $mutant_id = max_id({ table => 'mutant_info' });
                $save_edits{mutant_info} = 1;
            }
            else {
                $mutant_hashref = selectrow_hashref(
                    { table => 'mutant_info_edits', primary_key => $mutant_id, edits => 1 });
                if (scalar keys %{$mutant_hashref} == 0) {
                    $mutant_hashref =
                      selectrow_hashref({ table => 'mutant_info', primary_key => $mutant_id });

                    my ($mutant_symbol, $mutant_class_id) =
                      ($mutant_hashref->{symbol}, $mutant_hashref->{mutant_class_id});

                    # hack currently in place to inherit mutant class symbol
                    # when mutant_info symbol is missing
                    $mutant_symbol = get_class_symbol($mutant_class_id)
                      if ( $mutant_hashref->{symbol} eq "-"
                        or $mutant_hashref->{symbol} eq "");

                    $mutant_hashref->{symbol} = $mutant_symbol;
                }

                if (not defined $mutant_hashref->{has_alleles}) {

                    # count the number of alleles for the above mutant
                    # both from the original & edits tables
                    my %all_alleles = selectall_id('alleles', { mutant_id => $mutant_id });
                    $mutant_hashref->{has_alleles} = scalar keys %all_alleles;
                }

                $e_flag = undef;
                ($mutant_edits_hashref, $save_edits{mutant_info}, $e_flag) = cmp_hashref(
                    {
                        orig     => $mutant_hashref,
                        edits    => $mutant_edits_hashref,
                        is_admin => $anno_ref->{is_admin}
                    }
                );

                $save_edits{mutant_info} = 1
                  if (defined $anno_ref->{is_admin} and defined $e_flag);
            }

            $save_edits{loci} = 1
              if ($anno_ref->{loci}->{$locus_id}->{mutant_id} ne $mutant_id);

            $anno_ref->{loci}->{$locus_id}->{mutant_id} = $mutant_id;

            $anno_ref->{mutant_info}->{$mutant_id} =
              (defined $save_edits{mutant_info})
              ? $mutant_edits_hashref
              : $mutant_hashref;

            $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id} = $mutant_class_id;
        }
        else {
            if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}) {
                my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

                $anno_ref->{loci}->{$locus_id}->{mutant_id} = undef;
                $save_edits{loci} = 1;

                delete $anno_ref->{mutant_info}->{$mutant_id};

                my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};
                delete $anno_ref->{mutant_class}->{$mutant_class_id}
                  if (defined $mutant_class_id);
            }
        }

        $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = $params->{'has_structural_annot'};

        #save current value to db if save flag set
        if (defined $save_edits{loci}) {

            # if logged in as administrator, update/insert into main tables.
            $anno_ref->{loci}->{$locus_id}->{mod_date} = timestamp();
            if (defined $anno_ref->{is_admin}) {
                my $locus_obj = selectrow({ table => 'loci', primary_key => $locus_id });

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
                do('delete', 'loci_edits', { primary_key => $locus_id });

                # no longer define locus_id as an edit in session
                $anno_ref->{loci}->{$locus_id}->{is_edit} = undef;

                $result{'locus_edits'} = undef;
            }
            else {

                # if not admin, update/insert into edits tables
                my $locus_edits_obj =
                  selectrow({ table => 'loci_edits', primary_key => $locus_id });

                if (defined $locus_edits_obj) {
                    $locus_edits_obj = do(
                        'update',
                        'loci_edits',
                        {
                            hashref => $anno_ref->{loci}->{$locus_id},
                            obj     => $locus_edits_obj,
                        }
                    );
                }
                else {
                    $locus_edits_obj = do(
                        'insert',
                        'loci_edits',
                        {
                            locus_id  => $locus_id,
                            user_id   => $anno_ref->{user_id},
                            family_id => $anno_ref->{family_id},
                            edits     => JSON::to_json($anno_ref->{loci}->{$locus_id})
                        }
                    );
                }
                $result{'locus_edits'} = 1;
            }

            $result{'locus_id'} = $locus_id;
            $result{'mod_date'} = $anno_ref->{loci}->{$locus_id}->{mod_date};
        }

        if (defined $save_edits{mutant_info}) {
            $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};
            $anno_ref->{mutant_info}->{$mutant_id}->{mod_date} = timestamp();

            if (defined $anno_ref->{is_admin}) {
                my $mutant_obj = selectrow({ table => 'mutant_info', primary_key => $mutant_id });

                if (not defined $mutant_obj) {
                    $mutant_obj = do('insert', 'mutant_info', { mutant_id => $mutant_id, });
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
                do('delete', 'mutant_info_edits', { primary_key => $mutant_id });

                # no longer define mutant_id as an edit in session
                $anno_ref->{mutant_info}->{$mutant_id}->{is_edit} = undef;

                $result{'mutant_info_edits'} = undef;
            }
            else {
                my $mutant_edits_obj =
                  selectrow({ table => 'mutant_info_edits', primary_key => $mutant_id });

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
                            mutant_class_id =>
                              $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id},
                            edits => JSON::to_json($anno_ref->{mutant_info}->{$mutant_id})
                        }
                    );
                }
                $result{'mutant_info_edits'} = 1;
            }

            $result{'mutant_id'}       = $mutant_id;
            $result{'mutant_mod_date'} = $anno_ref->{mutant_info}->{$mutant_id}->{mod_date};
            $result{'has_alleles'}     = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};
            $result{'updated_mutant'}  = 1;

            $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

            if (defined $save_edits{mutant_class}) {
                if (defined $anno_ref->{is_admin}) {
                    my $mutant_class_obj =
                      selectrow({ table => 'mutant_class', primary_key => $mutant_class_id });

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
                    do('delete', 'mutant_class_edits', { primary_key => $mutant_class_id });

                    # no longer define mutant_id as an edit in session
                    $anno_ref->{mutant_class}->{$mutant_class_id}->{is_edit} = undef;

                    $result{'mutant_class_edits'} = undef;
                }
                else {
                    my $mutant_class_edits_obj =
                      selectrow({ table => 'mutant_class_edits', primary_key => $mutant_class_id });

                    if (defined $mutant_class_edits_obj) {
                        $mutant_class_edits_obj->set(
                            symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                            symbol_name =>
                              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                        );
                    }
                    else {
                        $mutant_class_edits_obj = do(
                            'insert',
                            'mutant_class_edits',
                            {
                                mutant_class_id => $mutant_class_id,
                                symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                                symbol_name =>
                                  $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                            }
                        );
                    }

                    $result{'mutant_class_edits'} = 1;
                }
            }
            $result{'mutant_class_id'}      = $mutant_class_id;
            $result{'updated_mutant_class'} = 1;
        }

        $session->param('anno_ref', $anno_ref);
        $session->flush;

        # HTML header
        #print $session->header(-type => 'text/plain');
        print $session->header(-type => 'application/json');

        $result{'updated'} = (
                 defined $save_edits{loci}
              or defined $save_edits{mutant_info}
              or defined $save_edits{mutant_class}
        ) ? 1 : undef;

        #? print "Update success! Changes submitted for administrator approval."
        #: print 'No changes to update.';

        print JSON::to_json(\%result);
    }
    else {

        #output the session
        #$row = $anno_ref->{loci}->{$locus_id};
        $tmpl->param(
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

            locus_id => $locus_id
        );

        if (defined $anno_ref->{is_admin}) {
            $tmpl->param(gene_symbol_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{gene_symbol_edit});
            $tmpl->param(func_annotation_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{func_annotation_edit});
            $tmpl->param(comment_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{comment_edit});
            $tmpl->param(gb_genomic_acc_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc_edit});
            $tmpl->param(gb_cdna_acc_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc_edit});
            $tmpl->param(gb_protein_acc_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{gb_protein_acc_edit});
            $tmpl->param(reference_pub_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{reference_pub_edit});
            $tmpl->param(mutant_id_edit => 1)
              if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id_edit});
        }

        if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
            and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
        {
            my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

            $tmpl->param(mutant_id => $mutant_id);
            my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

            $tmpl->param(
                mutant_class_id     => $mutant_class_id,
                mutant_class_symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                mutant_class_name   => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name},

                mutant_phenotype => $anno_ref->{mutant_info}->{$mutant_id}->{phenotype}
            );

            $anno_ref->{mutant_info}->{$mutant_id}->{symbol} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol}
              if ($anno_ref->{mutant_info}->{$mutant_id}->{symbol} eq "-");
            $tmpl->param(
                mutant_symbol        => $anno_ref->{mutant_info}->{$mutant_id}->{symbol},
                mapping_data         => $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data},
                mutant_reference_lab => $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab},
                mutant_reference_pub => $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub},
                mutant_mod_date      => $anno_ref->{mutant_info}->{$mutant_id}->{mod_date},

                has_alleles => $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles}
            );

            if (defined $anno_ref->{is_admin}) {
                $tmpl->param(mutant_symbol_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{symbol_edit});
                $tmpl->param(mutant_class_symbol_edit => 1)
                  if (defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_edit});

#$tmpl->param(mutant_class_name_edit => 1) if(defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name_edit});

                $tmpl->param(mutant_phenotype_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{phenotype_edit});
                $tmpl->param(mutant_reference_pub_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub_edit});
                $tmpl->param(mutant_reference_lab_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab_edit});
                $tmpl->param(mapping_data_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data_edit});

                $tmpl->param(has_alleles_edit => 1)
                  if (defined $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles_edit});
            }
        }
        $tmpl->param(username => $username);

        #delete $row->{is_edit};         # hack: ignore the 'is_edit' hashref key

        # HTML header
        print $session->header(-type => 'text/plain');

        print $tmpl->output;
    }
}

sub delete_locus {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY
    my $locus_obj       = selectrow({ table => 'loci',       primary_key => $locus_id });
    my $locus_edits_obj = selectrow({ table => 'loci_edits', primary_key => $locus_id });

    my $deleted             = undef;
    my $locus_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $locus_edits_obj) {
            $locus_edits_hashref =
              makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });
            $locus_edits_hashref->{is_deleted} = 1;

            $locus_edits_obj =
              do('update', 'loci_edits',
                { hashref => $locus_edits_hashref, obj => $locus_edits_obj });
        }
        else {    # otherwise, create a new edits_obj, with empty `edits` field
            $locus_edits_hashref->{is_deleted} = 1;
            $locus_edits_obj = do(
                'insert',
                'loci_edits',
                {
                    locus_id  => $locus_id,
                    family_id => $anno_ref->{family_id},
                    user_id   => $anno_ref->{user_id},
                    edits     => JSON::to_json($locus_edits_hashref)
                }
            );
        }
        $deleted = 1;
    }
    else {    # delete locus_obj and locus_edits_obj if 'admin'
        $locus_edits_obj->delete if (defined $locus_edits_obj);
        $locus_obj->delete       if (defined $locus_obj);

        delete $anno_ref->{loci}->{$locus_id};
        $deleted = 1;
    }

    if ($deleted) {
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        print 'Deleted!';
    }
    else {
        print 'Error!';
    }
}

sub undelete_locus {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my $locus_obj = selectrow({ table => 'loci', primary_key => $locus_id });
    my $locus_hashref = makerow_hashref({ obj => $locus_obj, table => 'loci' });

    my $locus_edits_obj = selectrow({ table => 'loci_edits', primary_key => $locus_id });
    my $locus_edits_hashref =
      makerow_hashref({ obj => $locus_edits_obj, table => 'loci_edits', edits => 1 });

    delete $locus_edits_hashref->{is_deleted};

    $locus_edits_obj =
      do('update', 'loci_edits', { hashref => $locus_edits_hashref, obj => $locus_edits_obj });

    if (scalar keys %{$locus_edits_hashref} == 0) {
        $locus_edits_obj->delete;
        $anno_ref->{loci}->{$locus_id} = $locus_hashref;
    }
    else {
        $anno_ref->{loci}->{$locus_id} = $locus_edits_hashref;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print 'Reverted!';
}

sub annotate_mutant {
    my ($session, $cgi, $save) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/annotate_mutant.tmpl");

    #gene_locus info should already be in the session.
    my $anno_ref  = $session->param('anno_ref');
    my $mutant_id = $cgi->param('mutant_id');

    if ($save) {
        my %result     = ();
        my %save_edits = ();
        my $e_flag     = undef;

        my $params = cgi_to_hashref({ cgi => $cgi, table => 'cgi', id => undef });

        # Storing mutant_info - Check if req mutant_info fields have been passed:
        # if true: get mutant_id from param or max(mutant_id) + 1 from db or increment if it already exists in the edits table
        # else: undef the 'mutant_id' associated with current locus_id (if any) and remove mutant_edits from anno_ref
        my ($mutant_id, $mutant_class_id);

        $mutant_class_id = $params->{'mutant_class_id'};
        my $mutant_class_hashref = {};
        my $mutant_class_edits_hashref =
          cgi_to_hashref({ cgi => $cgi, table => 'mutant_class', id => undef });

        my $mutant_class_symbol = $params->{'mutant_class_symbol'};

        # if mutant_class_id is not empty, just use the prexisting ID
        # otherwise, check and see if the mutant_class_symbol exists in the DB or not and get its ID
        if ($mutant_class_id eq "") {
            my $mutant_class_obj =
              selectrow({ table => 'mutant_class', where => { symbol => $mutant_class_symbol } });
            my $mutant_class_edits_obj = selectrow(
                {
                    table => 'mutant_class_edits',
                    where => { symbol => $mutant_class_symbol }
                }
            );

            $mutant_class_id =
              (defined $mutant_class_edits_obj)
              ? $mutant_class_edits_obj->mutant_class_id
              : $mutant_class_obj->mutant_class_id;
        }

        if (!$mutant_class_id) {
            $mutant_class_id = max_id({ table => 'mutant_class' });
            $save_edits{mutant_class} = 1;
        }
        else {
            $mutant_class_hashref = selectrow_hashref(
                { table => 'mutant_class_edits', primary_key => $mutant_class_id, edits => 1 });
            if (scalar keys %{$mutant_class_hashref} == 0) {
                $mutant_class_hashref =
                  selectrow_hashref({ table => 'mutant_class', primary_key => $mutant_class_id });
            }

            $e_flag = undef;
            ($mutant_class_edits_hashref, $save_edits{mutant_class}) = cmp_hashref(
                {
                    orig     => $mutant_class_hashref,
                    edits    => $mutant_class_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );
            $save_edits{mutant_class} = 1
              if (defined $anno_ref->{is_admin} and defined $e_flag);
        }

        $anno_ref->{mutant_class}->{$mutant_class_id} =
          ($save_edits{mutant_class})
          ? $mutant_class_edits_hashref
          : $mutant_class_hashref;

        # mutant already exists
        # check to see what has changed between the submission form and the database
        $mutant_id = $params->{'mutant_id'};
        my $mutant_edits_hashref =
          cgi_to_hashref({ cgi => $cgi, table => 'mutant_info', id => undef });
        my $mutant_hashref = {};
        my @alleles        = ();

        my $mutant_symbol = $params->{'mutant_symbol'};

        # if mutant_id is not empty, just use the prexisting ID
        # otherwise, check and see if the mutant_symbol exists in the DB or not and get its ID
        if ($mutant_id eq "") {
            my %mutant_ids = selectall_id('mutant_info', { mutant_class_id => $mutant_class_id });

            foreach my $id (sort { $a <=> $b } keys %mutant_ids) {
                my $mutant_hashref =
                  selectrow_hashref({ table => 'mutant_info', primary_key => $id });
                if (scalar keys %{$mutant_hashref} == 0) {
                    $mutant_hashref =
                      selectrow_hashref({ table => 'mutant_info_edits', primary_key => $id });
                }

                if ($mutant_hashref->{mutant_symbol} eq $mutant_symbol) {
                    $mutant_id = $id;
                    last;
                }
            }
        }

        if (!$mutant_id) {
            $mutant_id = max_id({ table => 'mutant_info' });
            $save_edits{mutant_info} = 1;
        }
        else {
            $mutant_hashref = selectrow_hashref(
                { table => 'mutant_info_edits', primary_key => $mutant_id, edits => 1 });
            if (scalar keys %{$mutant_hashref} == 0) {
                $mutant_hashref =
                  selectrow_hashref({ table => 'mutant_info', primary_key => $mutant_id });

                my ($mutant_symbol, $mutant_class_id) =
                  ($mutant_hashref->{symbol}, $mutant_hashref->{mutant_class_id});

                # hack currently in place to inherit mutant class symbol
                # when mutant_info symbol is missing
                $mutant_symbol = get_class_symbol($mutant_class_id)
                  if ( $mutant_hashref->{symbol} eq "-"
                    or $mutant_hashref->{symbol} eq "");

                $mutant_hashref->{symbol} = $mutant_symbol;
            }

            if (not defined $mutant_hashref->{has_alleles}) {

                # count the number of alleles for the above mutant
                # both from the original & edits tables
                my %all_alleles = selectall_id('alleles', { mutant_id => $mutant_id });
                $mutant_hashref->{has_alleles} = scalar keys %all_alleles;
            }

            $e_flag = undef;
            ($mutant_edits_hashref, $save_edits{mutant_info}, $e_flag) = cmp_hashref(
                {
                    orig     => $mutant_hashref,
                    edits    => $mutant_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            $save_edits{mutant_info} = 1
              if (defined $anno_ref->{is_admin} and defined $e_flag);
        }

        $save_edits{loci} = 1
          if ($anno_ref->{loci}->{$locus_id}->{mutant_id} ne $mutant_id);

        $anno_ref->{loci}->{$locus_id}->{mutant_id} = $mutant_id;

        $anno_ref->{mutant_info}->{$mutant_id} =
          (defined $save_edits{mutant_info})
          ? $mutant_edits_hashref
          : $mutant_hashref;

        $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id} = $mutant_class_id;

        if (defined $save_edits{mutant_info}) {
            $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};
            $anno_ref->{mutant_info}->{$mutant_id}->{mod_date} = timestamp();

            if (defined $anno_ref->{is_admin}) {
                my $mutant_obj = selectrow({ table => 'mutant_info', primary_key => $mutant_id });

                if (not defined $mutant_obj) {
                    $mutant_obj = do('insert', 'mutant_info', { mutant_id => $mutant_id, });
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
                do('delete', 'mutant_info_edits', { primary_key => $mutant_id });

                # no longer define mutant_id as an edit in session
                $anno_ref->{mutant_info}->{$mutant_id}->{is_edit} = undef;

                $result{'mutant_info_edits'} = undef;
            }
            else {
                my $mutant_edits_obj =
                  selectrow({ table => 'mutant_info_edits', primary_key => $mutant_id });

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
                            mutant_class_id =>
                              $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id},
                            edits => JSON::to_json($anno_ref->{mutant_info}->{$mutant_id})
                        }
                    );
                }
                $result{'mutant_info_edits'} = 1;
            }

            $result{'mutant_id'}       = $mutant_id;
            $result{'mutant_mod_date'} = $anno_ref->{mutant_info}->{$mutant_id}->{mod_date};
            $result{'has_alleles'}     = $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles};
            $result{'updated_mutant'}  = 1;

            $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

            if (defined $save_edits{mutant_class}) {
                if (defined $anno_ref->{is_admin}) {
                    my $mutant_class_obj =
                      selectrow({ table => 'mutant_class', primary_key => $mutant_class_id });

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
                    do('delete', 'mutant_class_edits', { primary_key => $mutant_class_id });

                    # no longer define mutant_id as an edit in session
                    $anno_ref->{mutant_class}->{$mutant_class_id}->{is_edit} = undef;

                    $result{'mutant_class_edits'} = undef;
                }
                else {
                    my $mutant_class_edits_obj =
                      selectrow({ table => 'mutant_class_edits', primary_key => $mutant_class_id });

                    if (defined $mutant_class_edits_obj) {
                        $mutant_class_edits_obj->set(
                            symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                            symbol_name =>
                              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                        );
                    }
                    else {
                        $mutant_class_edits_obj = do(
                            'insert',
                            'mutant_class_edits',
                            {
                                mutant_class_id => $mutant_class_id,
                                symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                                symbol_name =>
                                  $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                            }
                        );
                    }

                    $result{'mutant_class_edits'} = 1;
                }
            }
            $result{'mutant_class_id'}      = $mutant_class_id;
            $result{'updated_mutant_class'} = 1;
        }

        $session->param('anno_ref', $anno_ref);
        $session->flush;

        # HTML header
        #print $session->header(-type => 'text/plain');
        print $session->header(-type => 'application/json');

        $result{'updated'} = (
                 defined $save_edits{mutant_info}
              or defined $save_edits{mutant_class}
        ) ? 1 : undef;

        #? print "Update success! Changes submitted for administrator approval."
        #: print 'No changes to update.';

        print JSON::to_json(\%result);
    }
    else {
        $tmpl->param(is_mutant_edit => 1);
        $tmpl->param(mutant_id      => $mutant_id);
        my $mutant_class_id = $anno_ref->{mutant_info}->{$mutant_id}->{mutant_class_id};

        $tmpl->param(
            mutant_class_id     => $mutant_class_id,
            mutant_class_symbol => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
            mutant_class_name   => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name},
            mutant_phenotype    => $anno_ref->{mutant_info}->{$mutant_id}->{phenotype}
        );

        $anno_ref->{mutant_info}->{$mutant_id}->{symbol} =
          $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol}
          if ($anno_ref->{mutant_info}->{$mutant_id}->{symbol} eq "-");
        $tmpl->param(
            mutant_symbol        => $anno_ref->{mutant_info}->{$mutant_id}->{symbol},
            mapping_data         => $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data},
            mutant_reference_lab => $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab},
            mutant_reference_pub => $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub},
            mutant_mod_date      => $anno_ref->{mutant_info}->{$mutant_id}->{mod_date},
            has_alleles          => $anno_ref->{mutant_info}->{$mutant_id}->{has_alleles}
        );

        if (defined $anno_ref->{is_admin}) {
            $tmpl->param(mutant_symbol_edit => 1)
              if (defined $anno_ref->{mutant_info}->{$mutant_id}->{symbol_edit});
            $tmpl->param(mutant_class_symbol_edit => 1)
              if (defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_edit});

#$tmpl->param(mutant_class_name_edit => 1) if(defined $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name_edit});

            $tmpl->param(mutant_phenotype_edit => 1)
              if (defined $anno_ref->{mutant_info}->{$mutant_id}->{phenotype_edit});
            $tmpl->param(mutant_reference_pub_edit => 1)
              if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_pub_edit});
            $tmpl->param(mutant_reference_lab_edit => 1)
              if (defined $anno_ref->{mutant_info}->{$mutant_id}->{reference_lab_edit});
            $tmpl->param(mapping_data_edit => 1)
              if (defined $anno_ref->{mutant_info}->{$mutant_id}->{mapping_data_edit});
        }

        # HTML header
        print $session->header(-type => 'text/plain');

        print $tmpl->output;
    }
}


sub add_alleles {
    my ($session, $cgi) = @_;
    my $allele_list = $cgi->param('alleles_list');
    my $mutant_id   = $cgi->param('mutant_id');

    my $anno_ref = $session->param('anno_ref');

    $allele_list =~ s/\s+//;

    my $allele_id;
    my @new_alleles = split(/,/, $allele_list);
    my $track = 0;
  ALLELE: for my $allele_name (@new_alleles) {
        my $allele_obj =
          selectrow({ table => 'alleles', where => { allele_name => $allele_name } });

        my $new_allele_obj;
        if (defined $allele_obj) {
            $allele_id = $allele_obj->allele_id;
            my $allele_edits_obj =
              selectrow({ table => 'alleles_edits', primary_key => $allele_id });
            if (defined $allele_edits_obj) {
                my $allele_edits_hashref =
                  makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits' });

                if ($allele_edits_hashref->{is_deleted}) {

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
            my $allele_edits_objs = selectall_iter('alleles_edits');
            while (my $allele_edits_obj = $allele_edits_objs->next()) {
                my $allele_edits_hashref =
                  makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits' });

                if ($allele_edits_hashref->{allele_name} eq $allele_name) {
                    if ($allele_edits_hashref->{is_deleted}) {
                        $allele_edits_obj->delete;
                        goto INSERT if (not defined $anno_ref->{is_admin});
                    }
                    else {
                        next ALLELE;
                    }
                }
            }
        }

        # If not 'admin', get max(allele_id) after checking the 'alleles'
        # and 'alleles_edits' table; use it to populate a new edits entry
        if (not defined $anno_ref->{is_admin}) {
            $allele_id = max_id({ table => 'alleles' });
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
                    allele_id => $allele_id,
                    mutant_id => $mutant_id,
                    edits     => JSON::to_json($anno_ref->{alleles}->{$allele_id})
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

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header(-type => 'text/plain');

    #annotate($session, $cgi);
    print $track, ' allele', ($track >= 2 or $track == 0) ? 's' : '', ' added!';
}

sub annotate_alleles {
    my ($session, $cgi, $save) = @_;
    my $tmpl      = HTML::Template->new(filename => "./tmpl/annotate_alleles.tmpl");
    my $anno_ref  = $session->param('anno_ref');
    my $mutant_id = $cgi->param('mutant_id');

    #save current value to db if save flag set
    if ($save) {
        my %save_edits = ();
        my %result     = ();
        my $e_flag     = undef;
        for my $allele_id (keys %{ $anno_ref->{alleles} }) {
            my $allele_hashref = selectrow_hashref(
                { table => 'alleles_edits', primary_key => $allele_id, edits => 1 });

            if (scalar keys %{$allele_hashref} == 0) {
                $allele_hashref =
                  selectrow_hashref({ table => 'alleles', primary_key => $allele_id });
            }

            my $allele_edits_hashref =
              cgi_to_hashref({ cgi => $cgi, table => 'alleles', id => $allele_id });

            ($allele_edits_hashref, $save_edits{alleles}, $e_flag) = cmp_hashref(
                {
                    orig     => $allele_hashref,
                    edits    => $allele_edits_hashref,
                    is_admin => $anno_ref->{is_admin}
                }
            );

            $save_edits{alleles} = 1
              if (defined $anno_ref->{is_admin} and defined $e_flag);

            $anno_ref->{mutant_info}->{$mutant_id}->{allele_id} = $allele_id;
            $anno_ref->{alleles}->{$allele_id} =
              ($save_edits{alleles})
              ? $allele_edits_hashref
              : $allele_hashref;

            #save current value to db if save flag set
            if ($save_edits{alleles}) {
                if (defined $anno_ref->{is_admin}) {
                    my $allele_obj = selectrow({ table => 'alleles', primary_key => $allele_id });

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

                    do('delete', 'alleles_edits', { primary_key => $allele_id });

                    $anno_ref->{alleles}->{$allele_id}->{is_edit} = undef;

                    $result{'allele_edits'} = undef;
                }
                else {
                    my $allele_edits_obj =
                      selectrow({ table => 'alleles_edits', primary_key => $allele_id });

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
                                edits     => JSON::to_json($anno_ref->{alleles}->{$allele_id})
                            }
                        );
                    }
                    $result{'allele_edits'} = 1;
                }
            }
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        # HTML header
        print $session->header(-type => 'application/json');

        ($result{'updated'}) = (defined $save_edits{alleles}) ? 1 : undef;

        print JSON::to_json(\%result);
    }
    else {
        my $mutant_hashref = {};

        $mutant_hashref = selectrow_hashref(
            { table => 'mutant_info_edits', primary_key => $mutant_id, edits => 1 });
        if (scalar keys %{$mutant_hashref} == 0) {
            $mutant_hashref =
              selectrow_hashref({ table => 'mutant_info', primary_key => $mutant_id });
        }

        my $mutant_symbol   = $mutant_hashref->{symbol};
        my $mutant_class_id = $mutant_hashref->{mutant_class_id};
        $mutant_symbol = get_class_symbol($mutant_class_id)
          if ($mutant_hashref->{symbol} eq "-" or $mutant_hashref->{symbol} eq "");
        my $title = 'Annotate ' . $mutant_symbol . ' Alleles';

        my %all_alleles = selectall_id('alleles', { mutant_id => $mutant_id });

        my %deleted_alleles = ();
        foreach my $allele_id (sort { $a <=> $b } keys %all_alleles) {
            my %pick_edits = ();

            my $allele_edits_hashref = {};
            $allele_edits_hashref = selectrow_hashref(
                { table => 'alleles_edits', primary_key => $allele_id, edits => 1 });

            my $allele_hashref = {};
            $allele_hashref = selectrow_hashref({ table => 'alleles', primary_key => $allele_id });

            if ($allele_edits_hashref->{is_deleted}) {
                $deleted_alleles{$allele_id} = 1;
                $anno_ref->{alleles}->{$allele_id} =
                  (scalar keys %{$allele_edits_hashref} > 1)
                  ? $allele_edits_hashref
                  : $allele_hashref;
                next;
            }

            #$allele_hashref->{is_edit} = undef;

            ($allele_edits_hashref, $pick_edits{alleles}) = cmp_hashref(
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
        my @allele_ids           = sort { $a <=> $b } keys %{ $anno_ref->{alleles} };
        for my $allele_id (@allele_ids) {
            state $i;
            next unless ($anno_ref->{alleles}->{$allele_id}->{mutant_id} == $mutant_id);

            my $row = {};

            $row->{allele_id}         = $allele_id;
            $row->{allele_name}       = $anno_ref->{alleles}->{$allele_id}->{allele_name};
            $row->{alt_allele_names}  = $anno_ref->{alleles}->{$allele_id}->{alt_allele_names};
            $row->{reference_lab}     = $anno_ref->{alleles}->{$allele_id}->{reference_lab};
            $row->{altered_phenotype} = $anno_ref->{alleles}->{$allele_id}->{altered_phenotype};

            #$row->{tableRowClass}     = ($i++ % 2 == 0) ? "tableRowEven" : "tableRowOdd";
            $row->{tableRowClass} = "tableRowOdd";

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
        $tmpl->param(
            mutant_id            => $mutant_id,
            symbol               => $mutant_symbol,
            alleles_loop         => $alleles_loop,
            deleted_alleles_loop => $deleted_alleles_loop
        );
        print $session->header(-type => 'text/plain');

        print $tmpl->output;
    }
}

sub delete_allele {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $mutant_id = $cgi->param('mutant_id');
    my $allele_id = $cgi->param('allele_id');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY
    my $allele_obj       = selectrow({ table => 'alleles',       primary_key => $allele_id });
    my $allele_edits_obj = selectrow({ table => 'alleles_edits', primary_key => $allele_id });

    my $deleted              = undef;
    my $allele_edits_hashref = {};
    if (not defined $anno_ref->{is_admin}) {    # if not admin
        if (defined $allele_edits_obj) {
            $allele_edits_hashref =
              makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits', edits => 1 });
            $allele_edits_hashref->{is_deleted} = 1;

            $allele_edits_obj = do('update', 'alleles_edits',
                {
                    obj     => $allele_edits_obj,
                    hashref => $allele_edits_hashref,
                }
            );
        }
        else {    # else delete the edits object (since it is unapproved)
            $allele_edits_hashref->{is_deleted} = 1;
            $allele_edits_obj = do(
                'insert',
                'alleles_edits',
                {
                    allele_id => $allele_id,
                    mutant_id => $mutant_id,
                    edits     => JSON::to_json($allele_edits_hashref)
                }
            );
        }
        $deleted = 1;
    }
    else {    # delete allele_obj if 'admin'
        $allele_edits_obj->delete if (defined $allele_edits_obj);
        $allele_obj->delete       if (defined $allele_obj);
        $deleted = 1;
    }

    if ($deleted) {
        delete $anno_ref->{alleles}->{$allele_id};
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        print 'Deleted!';
    }
    else {
        print 'Error!';
    }
}

sub undelete_allele {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    my $allele_id = $cgi->param('allele_id');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY - update the edits entry and remove the is_deleted flag
    my $allele_obj = selectrow({ table => 'alleles', primary_key => $allele_id });
    my $allele_hashref = makerow_hashref({ obj => $allele_obj, table => 'alleles' });

    my $allele_edits_obj = selectrow({ table => 'alleles_edits', primary_key => $allele_id });
    my $allele_edits_hashref =
      makerow_hashref({ obj => $allele_edits_obj, table => 'alleles_edits', edits => 1 });

    delete $allele_edits_hashref->{is_deleted};

    $allele_edits_obj = do('update', 'alleles_edits',
        {
            hashref => $allele_edits_hashref,
            obj     => $allele_edits_obj,
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

sub structural_annotation {
    my ($session, $cgi) = @_;

    #my $locus_id = $cgi->param('locus_id');

    my $anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $locus_obj   = selectrow({ table => 'loci', primary_key => $locus_id });
    my $gene_locus  = $locus_obj->gene_locus;
    my $gene_symbol = $locus_obj->gene_symbol;

    my $ca_model_json = $cgi->param('model_json');
    my $tmpl = HTML::Template->new(filename => "./tmpl/structural_annotation.tmpl");

    my ($gff_locus_obj, $gene_models) = get_annotation_db_features($gene_locus, $gff_dbh);

    #when hooked into script - look for saved JSON in table if none passed as param
    #if no model JSON passed to script, create new from annotation gene model
    my ($ca_model_ds, $sa_object);
    if (!$ca_model_json) {    #JSON not passed as a parameter
        $sa_object =
          selectrow({ table => 'structural_annot_edits', where => { locus_id => $locus_id } });
        $sa_object = selectrow({ table => 'structural_annot', where => { locus_id => $locus_id } })
          if (not defined $sa_object);

        #print STDERR Dumper($sa_object);
        $ca_model_json = $sa_object->model if $sa_object;
    }
    if (!$ca_model_json) {    #no model JSON as a parameter or in the db
        ($ca_model_ds, $ca_model_json) = generate_initial_ca_model_ds($gene_models->[0]);
    }
    else {
        my $json_handler = JSON->new;
        $ca_model_ds = $json_handler->decode($ca_model_json);
    }
    my $ca_model_feature = create_ca_model_feature($ca_model_ds);
    my ($url, $map, $map_name) = create_ca_image_and_map(
        {
            locus_obj        => $gff_locus_obj,
            gene_models      => $gene_models,
            ca_model_feature => $ca_model_feature
        }
    );
    $map = add_js_event_to_map($map, $gene_models->[0]);
    my $ca_anno_loop = generate_table($ca_model_ds);

    $tmpl->param(
        img_path     => $url,
        map_name     => $map_name,
        map          => $map,
        ca_anno_loop => $ca_anno_loop,
        locus_id     => $locus_id,
        gene_locus   => $gene_locus,
        locus_type   => $ca_model_ds->{type},
        locus_seq_id => $ca_model_ds->{seq_id},
        locus_start  => $ca_model_ds->{start},
        locus_stop   => $ca_model_ds->{stop},
        locus_strand => $ca_model_ds->{strand},

        #model_json   => $ca_model_json,
    );

    print $tmpl->output;
}

sub submit_structural_annotation {
    my ($session, $cgi) = @_;
    my $gene_locus = $cgi->param('gene_locus');
    my $anno_ref   = $session->param('anno_ref');

    my %save_edits    = ();
    my $locus_obj     = selectrow({ table => 'loci', where => { gene_locus => $gene_locus } });
    my $locus_id      = $locus_obj->locus_id;
    my $ca_model_json = $cgi->param('model_json');

    #HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $struct_annot_hashref = {};

    $struct_annot_hashref =
      selectrow_hashref({ table => 'structural_annot_edits', where => { locus_id => $locus_id } });
    my $sa_id = $struct_annot_hashref->{sa_id};
    if (scalar keys %{$struct_annot_hashref} == 0) {
        $struct_annot_hashref =
          selectrow_hashref({ table => 'structural_annot', where => { locus_id => $locus_id } });
    }

    my $struct_annot_edits_hashref =
      cgi_to_hashref({ cgi => $cgi, table => 'structural_annot', id => undef });

    ($struct_annot_edits_hashref, $save_edits{structural_annot}) = cmp_hashref(
        {
            orig     => $struct_annot_hashref,
            edits    => $struct_annot_edits_hashref,
            is_admin => $anno_ref->{is_admin}
        }
    );

    if (defined $save_edits{structural_annot}) {
        my $struct_annot_edits_obj =
          selectrow({ table => 'structural_annot_edits', where => { locus_id => $locus_id } });
        if (defined $struct_annot_edits_obj) {
            $struct_annot_edits_obj->model($ca_model_json);
            $struct_annot_edits_obj->update;
        }
        else {
            $struct_annot_edits_obj = do(
                'insert',
                'structural_annot_edits',
                {
                    sa_id    => $sa_id,
                    locus_id => $locus_id,
                    model    => $ca_model_json,
                }
            );
            $struct_annot_edits_obj->update;
        }
        print "Structure edits saved!";
    }
    else {
        print "No changes to save!";
    }

    $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = 1;
    $session->param('anno_ref', $anno_ref);
    $session->flush;
}

sub review_annotation {
    my ($session, $cgi) = @_;

    my $tmpl = HTML::Template->new(
        filename          => "./tmpl/review_annotation.tmpl",
        die_on_bad_params => 0
    );
    my $anno_ref = $session->param('anno_ref');

    my $user_id   = $anno_ref->{user_id};
    my $family_id = $anno_ref->{family_id};
    my %all_loci =
      selectall_id('loci', { user_id => $anno_ref->{user_id}, family_id => $family_id });

    # loop through each locus_id and investigate associated mutants/alleles
    my $review_loop = [];
    foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
        my %pick_edits = ();

        my $locus_edits_hashref = {};
        $locus_edits_hashref =
          selectrow_hashref({ table => 'loci_edits', primary_key => $locus_id, edits => 1 });
        next if ($locus_edits_hashref->{is_deleted});

        my $locus_hashref = {};
        $locus_hashref = selectrow_hashref({ table => 'loci', primary_key => $locus_id });

        #$locus_hashref->{is_edit} = undef;

        ($locus_edits_hashref, $pick_edits{loci}) = cmp_hashref(
            {
                orig     => $locus_hashref,
                edits    => $locus_edits_hashref,
                is_admin => $anno_ref->{is_admin}
            }
        );

        my $row = {};
        if ($pick_edits{loci}) {
            $locus_edits_hashref->{is_edit} = 1;
            $row = $locus_edits_hashref;
        }
        else {
            $locus_hashref->{is_edit} = undef;
            $row = $locus_hashref;
        }

        my $mutant_id = $row->{mutant_id};

        if ($mutant_id) {
            my $mutant_hashref = {};
            my $mutant_info_obj;
            $mutant_info_obj =
              selectrow({ table => 'mutant_info_edits', primary_key => $mutant_id });
            if (defined $mutant_info_obj) {
                $mutant_hashref = JSON::from_json($mutant_info_obj->edits);
            }
            else {
                $mutant_info_obj = selectrow({ table => 'mutant_info', primary_key => $mutant_id });
                my ($mutant_symbol, $mutant_class_id) =
                  ($mutant_info_obj->symbol, $mutant_info_obj->mutant_class_id);

                # hack currently in place to inherit mutant class symbol
                # when mutant_info symbol is missing
                $mutant_symbol = get_class_symbol($mutant_class_id)
                  if ( $mutant_info_obj->symbol eq "-"
                    or $mutant_info_obj->symbol eq "");

                $mutant_hashref =
                  makerow_hashref({ obj => $mutant_info_obj, table => 'mutant_info' });
                $mutant_hashref->{symbol} = $mutant_symbol;
            }

            $row->{mutant_symbol} = $mutant_hashref->{symbol};
        }

        push(@$review_loop, $row);

    }
    $tmpl->param(
        review_loop => $review_loop,
        family_name => $anno_ref->{family}->{$family_id}->{family_name}
    );
    print $session->header;

    print $tmpl->output;
}

sub submit_annotation {
    my ($session, $cgi) = @_;

    my $family_name = $cgi->param('family_name');

    my $tmpl = HTML::Template->new(filename => "./tmpl/email_body_submit.tmpl");
    $tmpl->param(family_name => $family_name);
    my $email_body = $tmpl->output;

    my $success = send_email(
        {
            to_addr  => $admin_address,
            bcc_addr => $admin_address,
            subject  => "[EuCAP] $family_name Gene Family Annotation Submission",
            body     => $email_body
        }
    );

    print $cgi->header(-type => 'application/json');
    my %result =
      ($success)
      ? (
        'success' => 1,
        'message' =>
'Success! Please check your email for confirmation.<br />You may <a href="/cgi-bin/medicago/eucap/eucap.pl?action=logout">log out</a> of the system now.'
      )
      : ('success' => undef, 'message' => 'Error: Please notify website administrator');

    print JSON::to_json(\%result);
}

###################### Supporting subroutines #######################
sub promote_pending_user {
    my ($pending_user) = @_;

    eval {
        my $new_user = do(
            'insert', 'users',
            {
                name         => $pending_user->name,
                email        => $pending_user->email,
                username     => $pending_user->username,
                salt         => $pending_user->salt,
                hash         => $pending_user->hash,
                url          => $pending_user->url,
                organization => $pending_user->organization
            }
        );

        $pending_user->delete;
    };

    if ($@) {
        die "Error: Couldn't activate user. Please notify site administrator: $@\n\n";
    }
}

sub validation_hash {
    my ($user_info) = @_;

    my $t        = localtime;
    my $h        = Digest->new('SHA-1');
    my $hash_str = join " ", $user_info->{email}, $ENV{'REMOTE_ADDR'}, $user_info->{salt},
      $t->datetime;
    my $hash_str_base64 = encode_base64url($hash_str);
    $h->add($hash_str_base64);

    return $h->hexdigest;
}

sub check_email {
    my ($email, $ignore) = @_;

    #print $cgi->header(-type => 'application/json');
    print $cgi->header(-type => 'text/plain');

    my @results   = ();
    my $all_users = selectall_iter('users');
    while (my $user = $all_users->next()) {
        next if (defined $ignore and lc $ignore eq lc $user->email);
        if (lc $email eq lc $user->email) {
            print "false";

            #print JSON::to_json({ 'available' => 0, 'message' => 'Taken!' });
            exit;
        }
    }

    print "true";

    #print JSON::to_json({ 'available' => 1, 'message' => 'Available!' });
}

sub check_username {
    my ($username, $user_id, $ignore) = @_;

    #print $cgi->header(-type => 'application/json');
    print $cgi->header(-type => 'text/plain');

    my @results   = ();
    my $all_users = selectall_iter('users');
    while (my $user = $all_users->next()) {
        next if (defined $user_id and $user_id == $user->user_id);
        next if (defined $ignore and $ignore eq $user->username);

        if ($username eq $user->username) {
            print "false";

            #print JSON::to_json({ 'available' => 0, 'message' => 'Taken!' });
            exit;
        }
    }

    print "true";

    #print JSON::to_json({ 'available' => 1, 'message' => 'Available!' });
}

sub send_email {
    my ($arg_ref) = @_;

    my $send_cmd = "mailx -s '$arg_ref->{subject}' -b '$arg_ref->{bcc_addr}' $arg_ref->{to_addr}";
    return 0 unless (open MAIL, "| $send_cmd");

    print MAIL <<_EOM_;
$arg_ref->{body}
_EOM_

    close MAIL;
    return 1;
}

sub run_blast {
    my ($session, $cgi) = @_;

    my $tmpl        = HTML::Template->new(filename => "./tmpl/blast_results.tmpl");
    my $fasta_param = $cgi->param('fasta');
    my $seq_type    = $cgi->param('seqtype');
    my $evalue      = $cgi->param('evalue');

    ###### set up temp files##############
    my $blast_out_fh = File::Temp->new(
        TEMPLATE => 'tempXXXXXXXXX',
        DIR      => $WEBSERVER_TEMP_DIR,
        SUFFIX   => '.blast',
        UNLINK   => 1,
    ) or die;

    my $fasta_out_fh = File::Temp->new(
        TEMPLATE => 'tempXXXXXXXXX',
        DIR      => $WEBSERVER_TEMP_DIR,
        SUFFIX   => '.fasta',
        UNLINK   => 1,
    ) or die;

    print STDERR $fasta_out_fh->filename . "\n";
    print STDERR $blast_out_fh->filename . "\n";

    my $blast_program = $seq_type eq 'protein' ? 'blastp' : 'blastx';

    #need to do error checking if bad sequence passed
    my $string_fh = IO::String->new($fasta_param);
    my $seqio_in  = Bio::SeqIO->new(
        -fh     => $string_fh,
        -format => 'fasta',
    );
    my $seqio_out = Bio::SeqIO->new(
        -fh     => $fasta_out_fh,
        -format => 'fasta',
    );

    $seqio_out->write_seq($seqio_in->next_seq);

    system( "$BLASTALL -p $blast_program -d $PROTEOME_BLAST_DB -i "
          . $fasta_out_fh->filename
          . " -e $evalue  -v 20 -b 20 -o "
          . $blast_out_fh->filename);

    my $blast_parser = Bio::SearchIO->new(
        -format => 'blast',
        -file   => $blast_out_fh->filename
    );

    my $blast_results = {};

    my $result    = $blast_parser->next_result;
    my $hit_count = 0;
    $blast_results->{'total_hits'} = $result->num_hits;
    $blast_results->{'query_name'} = $result->query_name;
    while (my $hit = $result->next_hit) {
        $hit_count++;
        $blast_results->{hits}->{$hit_count} = {};

        my $description = $hit->description;
        $description =~
s/\s+chr\d{1}\s+\d+\-\d+\s+.*|\s+contig_\d+\s+\d+\-\d+\s+.*|\s+\w{2}\d+\.\d+\s+\d+\-\d+\s+.*//gs;

        $blast_results->{hits}->{$hit_count}->{hit_name}        = filter_hit_name($hit->name);
        $blast_results->{hits}->{$hit_count}->{hit_description} = $description;
        $blast_results->{hits}->{$hit_count}->{e_value}         = $hit->significance;
        $blast_results->{hits}->{$hit_count}->{score}           = $hit->raw_score;
        $blast_results->{hits}->{$hit_count}->{length}          = $hit->length;
    }

    #annotate($session, $cgi, 0, $blast_results);
    if ($blast_results) {
        $tmpl->param(
            blast_results => 1,
            total_hits    => $blast_results->{total_hits},
            query_name    => $blast_results->{query_name}
        );

        my $blast_loop = [];
        for my $hit (keys %{ $blast_results->{hits} }) {
            my $row = {};
            $row->{locus}       = $blast_results->{hits}->{$hit}->{hit_name};
            $row->{description} = $blast_results->{hits}->{$hit}->{hit_description};
            $row->{e_value}     = $blast_results->{hits}->{$hit}->{e_value};
            $row->{score}       = $blast_results->{hits}->{$hit}->{score};
            $row->{length}      = $blast_results->{hits}->{$hit}->{length};
            push(@$blast_loop, $row);
        }
        $tmpl->param(blast_loop => $blast_loop);
    }

    # HTTP HEADER
    print $session->header(-type => 'text/html');

    print $tmpl->output;
}

sub cmp_hashref {
    my ($arg_ref) = @_;

    my ($pick_edits, $e_flag) = (undef, undef);
    my @differences = data_diff($arg_ref->{orig}, $arg_ref->{edits});

    #warn Dumper(@differences);
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

sub cgi_to_hashref {
    my ($arg_ref) = @_;

    ####### $cgi->parameter        => 'database_column_name' #######
    my %table_columns = (
        'cgi' => {
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
            'mutant_id'            => 'mutant_id',
            'mutant_symbol'        => 'mutant_symbol',
            'mutant_class_id'      => 'mutant_class_id',
            'mutant_class_symbol'  => 'mutant_class_symbol',
            'mutant_class_name'    => 'mutant_class_name',
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
            'mod_date'             => 'mod_date',
            'has_structural_annot' => 'has_structural_annot'
        },
        'mutant_info' => {
            'mutant_symbol'        => 'symbol',
            'mutant_phenotype'     => 'phenotype',
            'mutant_reference_pub' => 'reference_pub',
            'mutant_reference_lab' => 'reference_lab',
            'mapping_data'         => 'mapping_data',
            'mutant_class_id'      => 'mutant_class_id',
            'has_alleles'          => 'has_alleles',
            'mutant_mod_date'      => 'mod_date'
        },
        'mutant_class' => {
            'mutant_class_symbol' => 'symbol',
            'mutant_class_name'   => 'symbol_name',
        },
        'alleles' => {
            'mutant_id'                        => "mutant_id",
            "allele_name_$arg_ref->{id}"       => "allele_name",
            "alt_allele_names_$arg_ref->{id}"  => "alt_allele_names",
            "reference_lab_$arg_ref->{id}"     => "reference_lab",
            "altered_phenotype_$arg_ref->{id}" => "altered_phenotype"
        },
        'structural_annot' => { 'model_json' => 'model' }
    );

    my %hash;
    my %params = $arg_ref->{cgi}->Vars;
    foreach my $param (keys %params) {
        if (defined $table_columns{ $arg_ref->{table} }{$param}) {
            $hash{ $table_columns{ $arg_ref->{table} }{$param} } = $params{$param};
        }
    }

    return \%hash;
}

sub get_loci {
    my ($arg_ref) = @_;

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    # EXECUTE THE QUERY
    my @locus_feats = $gff_dbh->get_features_by_name(
        -name  => "$arg_ref->{gene_locus}*",
        -types => 'gene'
    );

    # LOOP THROUGH RESULTS
    my @query_output = ();
    foreach my $locus_obj (@locus_feats) {
        my $id = $locus_obj->name;
        $id =~ s/\D+//gs;
        push @query_output,
          {
            'id'              => $id,
            'locus'           => $locus_obj->name,
            'func_annotation' => $locus_obj->notes
          };
    }
    @query_output = sort { $a->{id} <=> $b->{id} } @query_output;
    @query_output =
      (scalar @query_output >= $arg_ref->{limit})
      ? @query_output[ 0 .. --$arg_ref->{limit} ]
      : @query_output;

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

sub get_original_annotation {
    my ($locus) = @_;

    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $gff_dbh->get_features_by_name(-name => $locus, -types => 'gene');
    my ($notes) = $locus_feature_obj->notes if (defined $locus_feature_obj);

    (defined $notes) ? return $notes : return "";
}

sub filter_hit_name {

    #this has to be changed based on the defline of your proteome file
    #returns just the locus name
    my ($hit_name) = @_;
    $hit_name =~ /^IMGA\|(\S+)\.\d+/;
    if ($1) {
        return $1;
    }
    else {
        return $hit_name;
    }
}

sub timestamp {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $timestamp = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $year + 1900,
      $mon + 1, $mday, $hour,
      $min, $sec;

    return $timestamp;
}
############## Structural Annotation Subroutines #####################

sub generate_initial_ca_model_ds {
    my ($ref_gene_model) = @_;
    my @subfeatures = $ref_gene_model->get_SeqFeatures();
    @subfeatures =
      sort { $ref_gene_model->strand == 1 ? $a->start <=> $b->start : $b->start <=> $a->start }
      @subfeatures;
    my $comm_anno_ds = {};
    $comm_anno_ds->{subfeatures} = [];
    $comm_anno_ds->{type}        = $ref_gene_model->primary_tag;
    $comm_anno_ds->{seq_id}      = $ref_gene_model->seq_id;
    $comm_anno_ds->{start}       = $ref_gene_model->start;
    $comm_anno_ds->{stop}        = $ref_gene_model->stop;
    $comm_anno_ds->{strand}      = $ref_gene_model->strand;

    for my $subfeature (@subfeatures) {
        my $subfeature_ds = {};
        $subfeature_ds->{type}  = $subfeature->primary_tag;
        $subfeature_ds->{start} = $subfeature->start;
        $subfeature_ds->{stop}  = $subfeature->stop;
        push(@{ $comm_anno_ds->{subfeatures} }, $subfeature_ds);
    }
    my $json_handler         = JSON->new;
    my $comm_anno_model_json = $json_handler->encode($comm_anno_ds);
    return ($comm_anno_ds, $comm_anno_model_json);

}

sub Bio::Graphics::Panel::create_web_map {
    my $self = shift;
    my ($name, $linkrule, $titlerule, $targetrule) = @_;
    $name ||= 'map';
    my $boxes = $self->boxes;
    my (%track2link, %track2title, %track2target);

    my $map = qq(<map name="$name" id="$name">\n);
    foreach (@$boxes) {
        my ($feature, $left, $top, $right, $bottom, $track) = @$_;
        next unless $feature->can('primary_tag');
        my $primary_tag = $feature->primary_tag;
        next
          unless (($primary_tag)
            and (($primary_tag =~ /utr/i) or ($primary_tag =~ /cds/i)));

        my $lr = $track2link{$track} ||= (
            defined $track->option('link')
            ? $track->option('link')
            : $linkrule
        );
        next unless $lr;

        my $tr =
          exists $track2title{$track} ? $track2title{$track}
          : $track2title{$track} ||= (
            defined $track->option('title') ? $track->option('title')
            : $titlerule
          );
        my $tgr =
          exists $track2target{$track} ? $track2target{$track}
          : $track2target{$track} ||= (
            defined $track->option('target') ? $track->option('target')
            : $targetrule
          );

        my $href   = $self->make_link($lr,  $feature);
        my $alt    = $self->make_link($tr,  $feature);
        my $target = $self->make_link($tgr, $feature);
        $alt = $self->make_title($feature) unless defined $alt;

        my $a = $alt    ? qq(title="$alt" alt="$alt") : '';
        my $t = $target ? qq(target="$target")        : '';
        my $h = $href   ? qq(href="$href")            : '';

        $map .= qq(<area shape="rect" coords="$left,$top,$right,$bottom" $h $a $t/>\n);
    }
    $map .= "</map>\n";
    $map;
}

sub add_js_event_to_map {
    my ($map, $model_feature) = @_;
    my $end5 = $model_feature->strand == 1 ? $model_feature->start : $model_feature->end;
    my $new_map;
    my $string_io = IO::String->new($map);
    while (<$string_io>) {
        my $line = $_;
        if ($line =~ /^<area/) {

            #start = end5 - $stop = end3
            my ($start, $stop) = $line =~ /href="(\d+)-(\d+)"/;
            my $rel_end5 = $start - $end5 + 1;
            my $rel_end3 = $stop - $end5 + 1;
            $line =~
s/href="\d+-\d+"/onmouseover="displayCoords($start, $stop, $rel_end5, $rel_end3);setCursor();" onmouseout="restoreCursor()"/;
        }
        $new_map .= $line;
    }

    return $new_map;
}

sub generate_table {
    my ($comm_anno_ds) = @_;
    my $comm_anno_table = [];
    for my $subfeature (@{ $comm_anno_ds->{subfeatures} }) {
        my $row = {};
        $row->{CDS}   = $subfeature->{type} eq 'CDS' ? 1 : 0;
        $row->{start} = $subfeature->{start};
        $row->{stop}  = $subfeature->{stop};
        push(@{$comm_anno_table}, $row);
    }
    return $comm_anno_table;
}

sub get_annotation_db_features {
    my ($gene_locus, $gff_dbh) = @_;

    my ($gff_locus_obj) = $gff_dbh->get_features_by_name(-name => $gene_locus, -types => 'gene');
    my ($end5, $end3) = get_ends_from_feature($gff_locus_obj);
    my $segment = $gff_dbh->segment($gff_locus_obj->seq_id, $end5, $end3);
    my @gene_models = $segment->features(
        -name  => "$gene_locus*",
        -types => 'mRNA',
    );

    #will have to sort the gene models
    return ($gff_locus_obj, \@gene_models);
}

sub get_ends_from_feature {
    my ($gff_locus_obj) = @_;

    my ($end5, $end3) =
      $gff_locus_obj->strand == 1
      ? ($gff_locus_obj->start, $gff_locus_obj->end)
      : ($gff_locus_obj->end, $gff_locus_obj->start);

    #my $end3 = $locus_obj->strand == 1 ? $locus_obj->end : $locus_obj->start;

    return ($end5, $end3);
}

sub create_ca_model_feature {
    my ($ca_model_ds)         = @_;
    my $ca_model_subfeat_objs = [];
    my $seq_id                = $ca_model_ds->{seq_id};
    my $strand                = $ca_model_ds->{strand};
    for my $subfeature (@{ $ca_model_ds->{subfeatures} }) {
        my $subfeat_obj = Bio::Graphics::Feature->new(
            -seq_id => $seq_id,
            -start  => $subfeature->{start},
            -stop   => $subfeature->{stop},
            -type   => $subfeature->{type},
            -strand => 1,    #strand is flipped by *-1, if strand is 0, it doesn't work

        );
        push(@$ca_model_subfeat_objs, $subfeat_obj);
    }
    my $ca_model_feature = Bio::Graphics::Feature->new(
        -segments => $ca_model_subfeat_objs,
        -type     => 'mRNA',
        -strand   => $strand,
        -seq_id   => $seq_id,

    );

    return $ca_model_feature;
}

sub create_ca_image_and_map {
    my ($arg_ref) = @_;

    my ($l_end5, $l_end3) = get_ends_from_feature($arg_ref->{locus_obj});
    my ($c_end5, $c_end3) = get_ends_from_feature($arg_ref->{ca_model_feature});
    my ($end5,   $end3);
    if ($arg_ref->{locus_obj}->strand == 1) {
        $end5 = $c_end5 < $l_end5 ? $c_end5 : $l_end5;
        $end3 = $c_end3 > $l_end3 ? $c_end3 : $l_end3;
    }
    else {
        $end3 = $c_end5 > $l_end5 ? $c_end5 : $l_end5;
        $end5 = $c_end3 < $l_end3 ? $c_end3 : $l_end3;
    }

#flip will have to be dynamically controlled by the strand of the ca  model or the primary working model

    my $panel = Bio::Graphics::Panel->new(
        -length     => $arg_ref->{locus_obj}->length,
        -key_style  => 'between',
        -width      => 600,
        -pad_left   => 20,
        -pad_right  => 20,
        -pad_top    => 20,
        -pad_bottom => 20,
        -start      => $end5,
        -end        => $end3,
        -flip       => $arg_ref->{locus_obj}->strand == -1 ? 1 : 0,

    );

    $panel->add_track(
        arrow => Bio::SeqFeature::Generic->new(
            -start => $end5,
            -end   => $end3
        ),
        -bump   => 0,
        -double => 1,
        -tick   => 2,
        -key    => 'Abs Coords'
    );

    $panel->add_track(
        arrow => Bio::SeqFeature::Generic->new(
            -start  => $end5,
            -end    => $end3,
            -strand => $arg_ref->{locus_obj}->strand,
        ),
        -bump            => 0,
        -double          => 1,
        -tick            => 2,
        -relative_coords => 1,

        -key => 'Rel Coords'
    );

    $panel->add_track(
        $arg_ref->{locus_obj},
        -glyph       => 'box',
        -height      => 8,
        -description => 1,
        -label       => sub {
            my $feature = shift;
            my $alias   = $feature->attributes('Alias');
            return $alias;
        },
        -font2color => 'black',
        -bgcolor    => sub {
            my $feature = shift;
            my $note    = $feature->notes;
            if ($note =~ /^hypothetical/) {
                return "red";
            }
            elsif ($note =~ /^conserved hypothetical/) {
                return "blue";
            }
            elsif ($note =~ /^(expressed|unknown)/) {
                return "yellow";
            }
            elsif ($note =~ /transpos/) {
                return "black";
            }
            else {
                return "green";
            }
        },
        -fgcolor => 'black',
        -key     => 'IMGAG Gene Loci'
    );

    $panel->add_track(
        $arg_ref->{gene_models},
        -glyph     => 'gene',
        -connector => 'solid',
        -label     => sub {
            my $feature = shift;
            my $note    = $feature->display_name();
            return $note;
        },
        -height       => 10,
        -key          => 'IMGAG Gene Models',
        -utr_color    => 'white',
        -thin_utr     => 0,
        -fgcolor      => 'slateblue',
        -bgcolor      => 'skyblue',
        -box_subparts => 1,
    );

    $panel->add_track(
        $arg_ref->{ca_model_feature},
        -glyph        => 'gene',
        -connector    => 'solid',
        -label        => sub { my $f = shift; return $f->notes; },
        -description  => 0,
        -fgcolor      => "#0A910D",
        -bgcolor      => "lightgreen",
        -utr_color    => "white",
        -height       => 10,
        -font2color   => "black",
        -box_subparts => 1,
        -key          => 'Community Annotation',
    );

    my ($url, $map, $map_name) = $panel->image_and_map(
        -root    => $APACHE_DOC_ROOT,
        -url     => $WEBSERVER_TEMP_REL,
        -link    => '$start-$end',
        -mapname => 'eucap_map',

    );
    $panel->finished;
    return ($url, $map, $map_name);
}

#!/usr/local/bin/perl

use warnings;
use strict;

# CGI and authentication related modules
use CGI;
use CGI::Carp qw( fatalsToBrowser );
use CGI::Session;
use Authen::Passphrase::MD5Crypt;

# Page rendering Template modules
use Template;
use HTML::Template;

# Data related modules
use JSON;
use Switch;
use IO::String;
use Image::Size;
use File::Copy;
use File::Temp;
use File::Basename;
use Data::Dumper;

#Bioperl classes
use Bio::SeqIO;
use Bio::SearchIO;

#use Bio::DB::GFF;
use Bio::DB::SeqFeature::Store;
use Bio::SeqFeature::Generic;
use Bio::Graphics;
use Bio::Graphics::Feature;

#Class::DBI (ORM) classes
use lib ('./lib', '../');
use DBI;
use CA::CDBI;
use CA::users;
use CA::family;
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

# Third-party modules
use Data::Difference qw(data_diff);

# JCVI template page variables from MedicagoWeb.pm
use MedicagoWeb
  qw/:DEFAULT $site $home_page $side_menu $contact_email $body_tmpl $two_column_fluid_width $two_column_fixed_width/;

my $jcvi_template = $two_column_fixed_width;
my $title         = 'Medicago truncatula Genome Project :: Community Annotation';
my $project_name  = 'Medicago truncatula Community Annotation Portal';
my @breadcrumb    = ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => 'EuCAP' });
my @stylesheets =
  qw(https://ajax.googleapis.com/ajax/libs/jqueryui/1/themes/smoothness/jquery-ui.css /medicago/eucap/include/css/eucap.css /medicago/include/css/rounded_corners.css);
my @javascripts =
  qw(https://ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js http://ajax.googleapis.com/ajax/libs/jqueryui/1/jquery-ui.min.js /medicago/eucap/include/js/eucap.js /medicago/eucap/include/js/json.js /medicago/include/js/rounded_corners.js);

# Initialize JCVI template
my $jcvi_tt   = Template->new({ ABSOLUTE => 1, });
my $jcvi_vars = {};
my $FLAG      = 0;

#webserver path params
my $APACHE_DOC_ROOT    = $ENV{"DOCUMENT_ROOT"};
my $WEBSERVER_DOC_PATH = $APACHE_DOC_ROOT . "/medicago";
my $WEBSERVER_TEMP_REL = '/medicago/tmp';

# Allow max 5MB upload size
$CGI::POST_MAX = 1024 * 5000;

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
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql51-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';
my $CA_DB_PASSWORD = 'L0g!n2db';

#need this dbh for CGI::Session
my $ca_dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD)
  or die("cannot connect to CA database:$!");

CGI::Session->name("EuCAP_ID");
my $cgi = CGI->new;
my $session = CGI::Session->new("driver:mysql", $cgi, { Handle => $ca_dbh })
  or die(CGI::Session->errstr . "\n");
init($session, $cgi);
$session->flush;
unless ($session->param('~logged_in')) {
    login_page();
}
my $action   = $cgi->param('action');
my $locus_id = $cgi->param('locus_id');

if ($action eq 'select_family') {
    select_family($session, $cgi);
}
elsif ($action eq 'edit_profile') {
    edit_profile($session, $cgi);
}
elsif ($action eq 'update_profile') {
    edit_profile($session, $cgi);
}

# Locus/mutant specific actions
elsif ($action eq 'annotate') {
    annotate($session, $cgi);
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
    get_loci($cgi, $gene_locus);
    $FLAG = 1;
}
elsif ($action eq 'delete_locus') {
    delete_locus($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'run_blast') {
    run_blast($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'get_mutant_info') {
    my $mutant_sym = $cgi->param('term');
    get_mutant_info($cgi, $mutant_sym);
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

# Structural annotation specific actions
elsif ($action eq 'struct_anno') {
    structural_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'submit_annotation') {
    submit_annotation($session, $cgi);
}
elsif ($action eq 'submit_struct_anno') {
    submit_structural_annotation($session, $cgi);
    $FLAG = 1;
}
elsif ($action eq 'review_annotation') {
    review_annotation($session, $cgi);
}
elsif ($action eq 'final_submit') {
    final_submit($session, $cgi);
}
elsif ($action eq 'check_username') {
    my $user_id  = $cgi->param('user_id');
    my $username = $cgi->param('username');
    check_username($user_id, $username);
    $FLAG = 1;
}
elsif ($action eq 'logout') {
    logout($session, $cgi);
}
else {    # logged in and fall through the actions - then log out
    logout($session, $cgi, 'Sorry! System error. Please report to admin.');
}

# Print page only if action ne 'get_loci'
PROCESS_TMPL: if (!$FLAG) {
    $jcvi_vars->{title}        = $title;
    $jcvi_vars->{site}         = $site;
    $jcvi_vars->{home_page}    = $home_page;
    $jcvi_vars->{project_name} = $project_name;
    $jcvi_vars->{side_menu}    = $side_menu;
    $jcvi_vars->{breadcrumb}   = \@breadcrumb;
    $jcvi_vars->{stylesheets}  = \@stylesheets;
    $jcvi_vars->{javascripts}  = \@javascripts;

    $jcvi_tt->process($jcvi_template, $jcvi_vars) || $jcvi_tt->error();
}

$ca_dbh->disconnect if $ca_dbh;

# EuCAP subroutines
sub init {
    my ($session, $cgi) = @_;
    if ($session->param('~logged_in')) {
        return 1;
    }
    unless ($cgi->param('action')) {
        login_page();
        goto PROCESS_TMPL;
    }
    my $username = $cgi->param('username');
    my $password = $cgi->param('password');
    my ($user) = CA::users->search(username => $username);
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
    }
}

sub login_page {
    my ($is_err_msgor, $error_string) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/login.tmpl");
    if ($is_err_msgor) {
        $tmpl->param(error        => 1);
        $tmpl->param(error_string => $error_string);
    }
    print $session->header;

    $jcvi_vars->{main_content} = $tmpl->output;
}

sub logout {
    my ($session, $cgi) = @_;
    $session->clear(["~logged_in"]);
    $session->flush;
    login_page(1, "Logged out - Thank you");
}

sub select_family {
    my ($session, $cgi) = @_;
    my $title    = "Select Gene Family";
    my $tmpl     = HTML::Template->new(filename => "./tmpl/select_family.tmpl");
    my $anno_ref = $session->param('anno_ref');

    my $user_id = (defined $anno_ref->{is_admin}) ? 0 : $anno_ref->{user_id};
    &get_user_info($anno_ref, $user_id);
    my $username = $anno_ref->{user}->{$user_id}->{username};

    my $fams =
      ($username eq "admin")
      ? CA::family->retrieve_all
      : CA::family->search(user_id => $anno_ref->{user_id});

    my $gene_family_list = [];
    while (my $fam = $fams->next) {
        my $family_id = $fam->family_id;
        my $row       = {
            user_id           => $fam->user_id,
            family_id         => $family_id,
            gene_class_symbol => $fam->gene_class_symbol,
            family_name       => $fam->family_name,
            description       => $fam->description
        };
        push(@$gene_family_list, $row);

        if (not defined $anno_ref->{is_admin}) {
            $anno_ref->{family_id}                                 = $family_id;
            $anno_ref->{family}->{$family_id}->{family_name}       = $fam->family_name;
            $anno_ref->{family}->{$family_id}->{gene_class_symbol} = $fam->gene_class_symbol;
            $anno_ref->{family}->{$family_id}->{description}       = $fam->description;
        }
    }

    $tmpl->param(
        gene_family_radio => $gene_family_list,
        image_name        => $anno_ref->{user}->{$user_id}->{photo_file_name},
        name              => $anno_ref->{user}->{$user_id}->{name},
        organization      => $anno_ref->{user}->{$user_id}->{organization},
        email             => $anno_ref->{user}->{$user_id}->{email},
        url               => $anno_ref->{user}->{$user_id}->{url},
    );

    if (defined $anno_ref->{is_admin}) {
        $tmpl->param(is_admin => 1);
        undef $anno_ref->{user_id};
        undef $anno_ref->{user};
        undef $anno_ref->{family_id};
        undef $anno_ref->{family};
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header;

    push @breadcrumb, ({ 'link' => '#', 'menu_name' => $title });
    $jcvi_vars->{title}       = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{page_header} = "Select Gene Family";
    $jcvi_vars->{top_menu}    = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub edit_profile {
    my ($session, $cgi) = @_;
    my $title    = "Edit User Profile";
    my $tmpl     = HTML::Template->new(filename => "./tmpl/edit_profile.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my ($userInfoUpdated, $photoUploaded) = (undef, undef);

    &get_user_info($anno_ref, 0) if (defined $anno_ref->{is_admin});
    my $user_id       = $anno_ref->{user_id};
    my $username      = $anno_ref->{user}->{$user_id}->{username};
    my $update_status = "";
    my ($username_err_msg, $email_err_msg, $url_err_msg, $photo_err_msg) = ("", "", "", "");
    my ($username_valid, $email_valid, $url_valid, $photo_valid);

    if ($action eq "update_profile") {
        my $user_id          = $cgi->param('user_id');
        my $new_username     = $cgi->param('username');
        my $new_name         = $cgi->param('name');
        my $new_organization = $cgi->param('organization');
        my $new_email        = $cgi->param('email');
        my $new_url          = $cgi->param('url');

        my $username_valid = $cgi->param('username_valid');
        my $email_valid    = $cgi->param('email_valid');
        my $url_valid      = $cgi->param('url_valid');

        my $new_photo   = $cgi->param('photo');
        my $photo_valid = 1;

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
                open UPLOADFILE, ">", "$WEBSERVER_TEMP_DIR/$new_photo_file_name"
                  or die "$!";
                binmode UPLOADFILE;
                while (<$upload_filehandle>) {
                    print UPLOADFILE $_;
                }
                close UPLOADFILE;

                my ($width, $height) = imgsize("$WEBSERVER_TEMP_DIR/$new_photo_file_name");
                if ($width <= 200 and $height <= 200) {
                    File::Copy::move(
                        "$WEBSERVER_TEMP_DIR/$new_photo_file_name",
                        "$CA_USER_IMAGE_PATH/$new_photo_file_name"
                    ) or die "$!";
                    $photoUploaded = 1;
                }
                else {
                    $photo_valid = 0;
                }
            }
        }

        $anno_ref->{user}->{$user_id}->{username}        = $new_username;
        $anno_ref->{user}->{$user_id}->{name}            = $new_name;
        $anno_ref->{user}->{$user_id}->{organization}    = $new_organization;
        $anno_ref->{user}->{$user_id}->{email}           = $new_email;
        $anno_ref->{user}->{$user_id}->{url}             = $new_url;
        $anno_ref->{user}->{$user_id}->{photo_file_name} = $new_photo_file_name
          if (defined $photoUploaded);

        if ($username_valid and $email_valid and $url_valid and $photo_valid) {
            &update_user_info($anno_ref, $user_id);
            $userInfoUpdated = 1;
            $update_status   = 'Profile updated!';
        }
        else {
            $username_err_msg = 'Taken!'   if (not $username_valid);
            $email_err_msg    = 'Invalid!' if (not $email_valid);
            $url_err_msg      = 'Invalid!' if (not $url_valid);
            $photo_err_msg = 'Please check size/dimensions of uploaded picture'
              if (not $photo_valid);
            $update_status = 'Please check your input!';
        }
    }

    &get_user_info($anno_ref, $user_id) if (defined $userInfoUpdated);

    my $photo_file_name = $anno_ref->{user}->{$user_id}->{photo_file_name};
    my ($image_name) = $anno_ref->{user}->{$user_id}->{photo_file_name};

    $tmpl->param(
        user_id          => $user_id,
        username         => $anno_ref->{user}->{$user_id}->{username},
        name             => $anno_ref->{user}->{$user_id}->{name},
        organization     => $anno_ref->{user}->{$user_id}->{organization},
        email            => $anno_ref->{user}->{$user_id}->{email},
        url              => $anno_ref->{user}->{$user_id}->{url},
        image_name       => $anno_ref->{user}->{$user_id}->{photo_file_name},
        update_status    => $update_status,
        username_err_msg => $username_err_msg,
        email_err_msg    => $email_err_msg,
        url_err_msg      => $url_err_msg,
        photo_err_msg    => $photo_err_msg
    );
    print $session->header;

    push @javascripts, "/medicago/eucap/include/js/edit_profile.js";
    push @breadcrumb,
      (
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        { 'link' => '#', 'menu_name' => $title }
      );
    $jcvi_vars->{title}    = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $anno_ref->{user}->{$user_id}->{username} . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub annotate {
    my ($session, $cgi, $blast_results) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/annotate.tmpl");
    my $anno_ref = $session->param('anno_ref');

    my ($user_id, $family_id) = ($cgi->param('user_id'), $cgi->param('family_id'));
    if (defined $anno_ref->{is_admin}) {
        &get_user_info($anno_ref, $user_id);
        &get_family_info($anno_ref, $family_id);
    }

    my $user     = CA::users->retrieve($anno_ref->{user_id});
    my $family   = CA::family->retrieve($anno_ref->{family_id});
    my $username = (defined $anno_ref->{is_admin}) ? "admin" : $user->username;
    my $title    = 'Annotate ' . $family->gene_class_symbol . ' Gene Family';

    # coming in from the select family action - the database is the most up to data source
    # count the number of loci for this family (uniq of all loci in the original & edits table
    my @annotated_loci = CA::loci->search(
        user_id   => $anno_ref->{user_id},
        family_id => $anno_ref->{family_id}
    );

    my @edited_loci = CA::loci_edits->search(
        user_id   => $anno_ref->{user_id},
        family_id => $anno_ref->{family_id}
    );

    my %all_loci = ();
    $all_loci{ $_->locus_id } = 1 foreach ((@annotated_loci, @edited_loci));

    # loop through each locus_id and investigate associated mutants/alleles
    foreach my $locus_id (sort { $a <=> $b } keys %all_loci) {
        my $locus_edits_obj = CA::loci_edits->retrieve(
            locus_id  => $locus_id,
            user_id   => $anno_ref->{user_id},
            family_id => $anno_ref->{family_id}
        );

        my $locus_hashref = {};
        if (defined $locus_edits_obj) {
            my $edits = $locus_edits_obj->edits;
            if ($edits eq "") {    # gene has been deleted if $edits exists and is empty
                delete $anno_ref->{loci}->{$locus_id};
                next;
            }
            $locus_hashref = JSON::from_json($locus_edits_obj->edits);
        }
        else {
            my $locus_obj = CA::loci->retrieve(
                locus_id  => $locus_id,
                user_id   => $anno_ref->{user_id},
                family_id => $anno_ref->{family_id},
            );
            $locus_hashref = caObj_to_hashref($locus_obj, 'loci')
              if (defined $locus_obj);
        }

        $anno_ref->{loci}->{$locus_id} = $locus_hashref;

        if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
            and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
        {
            my $mutant_id        = $anno_ref->{loci}->{$locus_id}->{mutant_id};
            my $mutant_edits_obj = CA::mutant_info_edits->retrieve($mutant_id);

            my $mutant_hashref = {};
            if (defined $mutant_edits_obj) {
                my $edits = $mutant_edits_obj->edits;
                if ($edits eq "") {    # mutant info has been deleted. unassociate with locus
                    undef $anno_ref->{loci}->{$locus_id}->{mutant_id};

                    # delete mutant_info
                    delete $anno_ref->{mutant}->{$mutant_id};
                    next;
                }
                $mutant_hashref = JSON::from_json($mutant_edits_obj->edits);
            }
            else {
                my $mutant_obj = CA::mutant_info->retrieve($mutant_id);
                $mutant_hashref = caObj_to_hashref($mutant_obj, 'mutant_info')
                  if (defined $mutant_obj);
            }

            $anno_ref->{mutant}->{$mutant_id} = $mutant_hashref;

            # count the number of alleles for the above mutant
            # both from the original & edits tables
            my @annotated_alleles = CA::alleles->search(mutant_id => $mutant_id);
            my @edited_alleles = CA::alleles_edits->search(mutant_id => $mutant_id);

            my %all_alleles = ();
            $all_alleles{ $_->allele_id } = 1 foreach ((@annotated_alleles, @edited_alleles));
            $anno_ref->{mutant}->{$mutant_id}->{has_alleles} = scalar keys %all_alleles;

            my $mutant_class_id        = $anno_ref->{mutant}->{$mutant_id}->{mutant_class_id};
            my $mutant_class_edits_obj = CA::mutant_class_edits->retrieve($mutant_class_id);

            my $mutant_class_hashref = {};
            if (defined $mutant_class_edits_obj) {
                my $symbol      = $mutant_class_edits_obj->symbol;
                my $symbol_name = $mutant_class_edits_obj->symbol_name;
                if ($symbol eq undef and $symbol_name eq undef)
                {    # mutant class info has been deleted. unassociate with mutant
                    delete $anno_ref->{mutant_class}->{$mutant_class_id};
                    next;
                }
                $mutant_class_hashref = caObj_to_hashref($mutant_class_edits_obj, 'mutant_class');
            }
            else {
                my $mutant_class_obj = CA::mutant_class->retrieve($mutant_class_id);
                $mutant_class_hashref = caObj_to_hashref($mutant_class_obj, 'mutant_class')
                  if (defined $mutant_class_obj);
            }

            $anno_ref->{mutant_class}->{$mutant_class_id} = $mutant_class_hashref;
        }
    }
    $session->param('anno_ref', $anno_ref);
    $session->flush;

    #now output the session
    my $annotation_summary_loop = [];
    my $i                       = 0;
    my @locus_ids               = sort { $a <=> $b } keys %{ $anno_ref->{loci} };
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

        push(@$annotation_summary_loop, $summary_row);
    }

    $tmpl->param(annotation_summary_loop => $annotation_summary_loop);
    print $session->header;

    #print $tmpl->output;
    push @javascripts, "/medicago/eucap/include/js/annotate.js";
    push @breadcrumb,
      (
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        { 'link' => '#', 'menu_name' => $title }
      );
    $jcvi_vars->{title}       = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{page_header} = 'Community Annotation for ' . $family->family_name . ' Gene Family';
    $jcvi_vars->{top_menu}    = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub add_loci {
    my ($session, $cgi) = @_;
    my $loci_list = $cgi->param('loci_list');
    my $anno_ref  = $session->param('anno_ref');

    $loci_list =~ s/^\s+|\s+$//;

    my @new_loci = split /,/, $loci_list;
    my $track    = 0;
    my $locus_id = "";
  LOCUS: for my $gene_locus (@new_loci) {

        #next unless ($gene_locus =~ /^Medtr[1-8]g\d+|^\S+_\d+|^contig_\d+_\d+/);
        next
          unless ($gene_locus =~ /\bMedtr\d{1}g\d+\b/
            or $gene_locus =~ /\b\w{2}\d+_\d+\b/
            or $gene_locus =~ /\bcontig_\d+_\d+\b/);

        my ($locus_obj) = CA::loci->retrieve(
            gene_locus => $gene_locus,
            user_id    => $anno_ref->{user_id},
            family_id  => $anno_ref->{family_id}
        );
        if (defined $locus_obj) {
            $locus_id = $locus_obj->locus_id;
            my $locus_edits_obj = CA::loci_edits->retrieve(
                locus_id  => $locus_id,
                user_id   => $anno_ref->{user_id},
                family_id => $anno_ref->{family_id}
            );
            my $edits = $locus_edits_obj->edits if (defined $locus_edits_obj);

            if (defined $locus_edits_obj and $edits eq "") {
                $locus_edits_obj->delete;
                goto INSERT;
            }
            next LOCUS;
        }
        else {
            my $locus_edits_objs = CA::loci_edits->retrieve_all();
            while (my $locus_edits_obj = $locus_edits_objs->next()) {
                my $locus_edits_hashref = JSON::from_json($locus_edits_obj->edits);

                next LOCUS
                  if ($locus_edits_hashref->{gene_locus} eq $gene_locus);
            }
        }

        if ($locus_id) {
            $locus_id += 1;
        }
        else {
            my $max_locus_id = &get_max_id('locus_id', 'v2_loci');
            $locus_id = $max_locus_id + 1;

            my $check = CA::loci_edits->retrieve($locus_id);
            until (not defined $check) {
                my $edits_max_locus_id = &get_max_id('locus_id', 'v2_loci_edits');
                $locus_id = $edits_max_locus_id + 1
                  if ($locus_id <= $edits_max_locus_id);

                $check = CA::loci_edits->retrieve($locus_id);
            }
        }

      INSERT:
        my $orig_func_annotation = get_original_annotation($gene_locus);

        #my $locus_id = $new_locus_row->locus_id;
        $anno_ref->{loci}->{$locus_id}->{gene_locus}           = $gene_locus;
        $anno_ref->{loci}->{$locus_id}->{orig_func_annotation} = $orig_func_annotation;
        $anno_ref->{loci}->{$locus_id}->{gene_symbol}          = q{};
        $anno_ref->{loci}->{$locus_id}->{func_annotation}      = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc}       = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc}          = q{};
        $anno_ref->{loci}->{$locus_id}->{gb_protein_acc}       = q{};
        $anno_ref->{loci}->{$locus_id}->{reference_pub}        = q{};
        $anno_ref->{loci}->{$locus_id}->{mod_date}             = &timestamp();
        $anno_ref->{loci}->{$locus_id}->{comment}              = q{};
        $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = 0;

        my $new_locus_row = CA::loci_edits->insert(
            {
                locus_id  => $locus_id,
                user_id   => $anno_ref->{'user_id'},
                family_id => $anno_ref->{'family_id'},
                edits     => JSON::to_json($anno_ref->{loci}->{$locus_id})
            }
        );

        $track++;

        #push @return_vals, JSON::to_json($anno_ref->{loci}->{$locus_id});
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header(-type => 'text/plain');

    #annotate($session, $cgi);
    print $track, ' loc', ($track > 2 or $track == 0) ? 'i' : 'us', ' added!';
}

sub annotate_locus {
    my ($session, $cgi, $save) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/annotate_locus.tmpl");

    #gene_locus info should already be in the session.
    my $anno_ref = $session->param('anno_ref');

    if ($save) {
        my %result = ();
        my %save_edits =
          ();    # hash to store a flag for each type of feature (loci, mutant_info, mutant_class)
                 # used to track if there are changes or not

# Storing loci is straightforward, there should already be a 'locus_id' for a newly instantiated gene.
        my $locus_hashref = {};
        my $curr_locus_obj = CA::loci_edits->retrieve(
            locus_id  => $locus_id,
            user_id   => $anno_ref->{user_id},
            family_id => $anno_ref->{family_id}
        );
        if ( defined $curr_locus_obj ) {
            $locus_hashref = JSON::from_json($curr_locus_obj->edits);
        }
        else {
            $curr_locus_obj = CA::loci->retrieve(
                locus_id  => $locus_id,
                user_id   => $anno_ref->{user_id},
                family_id => $anno_ref->{family_id}
            );
            $locus_hashref = caObj_to_hashref($curr_locus_obj, 'loci');
        }
        my $locus_edits_hashref = cgi_to_hashref($cgi, 'loci', undef);

        my @differences = data_diff($locus_hashref, $locus_edits_hashref);

        foreach my $diff (@differences) {
            $save_edits{loci} = 1 if (defined $diff->{b});
        }

        $anno_ref->{loci}->{$locus_id} =
          (defined $save_edits{loci}) ? $locus_edits_hashref : $locus_hashref;

        # Storing mutant_info - Check if req mutant_info fields have been passed:
        # if true: get mutant_id from param or max(mutant_id) + 1 from db or increment if it already exists in the edits table
        # else: undef the 'mutant_id' associated with current locus_id (if any) and remove mutant_edits from anno_ref
        my ($mutant_id, $mutant_class_id);
        if (    $cgi->param('mutant_symbol') ne ""
            and $cgi->param('mutant_class_symbol')  ne ""
            and $cgi->param('mutant_class_name')    ne ""
            and $cgi->param('mutant_phenotype')     ne ""
            and $cgi->param('mutant_reference_pub') ne "")
        {

            # mutant already exists
            # check to see what has changed between the submission form and the database
            my $mutant_hashref       = {};
            my $mutant_edits_hashref = {};
            my @alleles              = ();

            if ($cgi->param('mutant_id') ne "") {
                $mutant_id = $cgi->param('mutant_id');

                if (defined CA::mutant_info_edits->retrieve($mutant_id)) {
                    my $mutant_info_obj = CA::mutant_info_edits->retrieve($mutant_id);
                    $mutant_hashref = JSON::from_json($mutant_info_obj->edits);
                }
                else {
                    my $mutant_info_obj = CA::mutant_info->retrieve($mutant_id);
                    my ($mutant_symbol, $mutant_class_id) =
                      ($mutant_info_obj->symbol, $mutant_info_obj->mutant_class_id);

                    # hack currently in place to inherit mutant class symbol
                    # when mutant_info symbol is missing
                    $mutant_symbol = fix_missing_mutant_symbol($mutant_symbol, $mutant_class_id)
                      if ( $mutant_info_obj->symbol eq "-"
                        or $mutant_info_obj->symbol eq "");

                    $mutant_hashref = caObj_to_hashref($mutant_info_obj, 'mutant_info');
                    $mutant_hashref->{symbol} = $mutant_symbol;
                }

                if(not defined $mutant_hashref->{has_alleles}) {
                    # count the number of alleles for the above mutant
                    # both from the original & edits tables
                    my @annotated_alleles = CA::alleles->search(mutant_id => $mutant_id);
                    my @edited_alleles = CA::alleles_edits->search(mutant_id => $mutant_id);

                    my %all_alleles = ();
                    $all_alleles{ $_->allele_id } = 1 foreach ((@annotated_alleles, @edited_alleles));
                    $mutant_hashref->{has_alleles} = scalar keys %all_alleles;
                }

                $mutant_edits_hashref = cgi_to_hashref($cgi, 'mutant_info', undef);

                my @differences = data_diff($mutant_hashref, $mutant_edits_hashref);

                foreach my $diff (@differences) {
                    warn Dumper($diff);
                    $save_edits{mutant_info} = 1 if (defined $diff->{b});
                }
            }
            else {    # new mutant, instantiate into mutant_info_edits
                my $max_mutant_id = &get_max_id('mutant_id', 'v2_mutant_info');
                $mutant_id = $max_mutant_id + 1;

                my $check = CA::mutant_info_edits->retrieve($mutant_id);
                until (not defined $check) {
                    my $edits_max_mutant_id = &get_max_id('mutant_id', 'v2_mutant_info_edits');
                    $mutant_id = $edits_max_mutant_id + 1
                      if ($mutant_id <= $edits_max_mutant_id);

                    $check = CA::mutant_info_edits->retrieve($mutant_id);
                }

                $save_edits{mutant_info} = 1;
            }

            $save_edits{loci} = 1
              if ($locus_hashref->{mutant_id} ne $mutant_id);

            $anno_ref->{loci}->{$locus_id}->{mutant_id} = $mutant_id;
            $anno_ref->{mutant}->{$mutant_id} =
              (defined $save_edits{mutant_info})
              ? $mutant_edits_hashref
              : $mutant_hashref;

            my $mutant_class_hashref       = {};
            my $mutant_class_edits_hashref = {};
            if ($cgi->param('mutant_class_id') ne "") {
                $mutant_class_id = $cgi->param('mutant_class_id');

                if (defined CA::mutant_class_edits->retrieve($mutant_class_id)) {
                    my $mutant_class_obj = CA::mutant_class_edits->retrieve($mutant_class_id);
                    $mutant_class_hashref = caObj_to_hashref($mutant_class_obj, 'mutant_class');
                }
                else {
                    my $mutant_class_obj = CA::mutant_class->retrieve($mutant_class_id);
                    $mutant_class_hashref = caObj_to_hashref($mutant_class_obj, 'mutant_class')
                      if (defined $mutant_class_obj);
                }

                $mutant_class_edits_hashref = cgi_to_hashref($cgi, 'mutant_class', undef);

                my @differences = data_diff($mutant_class_hashref, $mutant_class_edits_hashref);

                foreach my $diff (@differences) {
                    $save_edits{mutant_class} = 1 if (defined $diff->{b});
                }
            }
            else {

                # possible new mutant_class. First check and see if mutant_class_symbol exists
                my $mutant_class_symbol = $cgi->param('mutant_class_symbol');
                if (defined CA::mutant_class_edits->search(symbol => $mutant_class_symbol)) {
                    my $mutant_class_obj =
                      CA::mutant_class_edits->search(symbol => $mutant_class_symbol)->first;
                    $mutant_class_hashref = caObj_to_hashref($mutant_class_obj, 'mutant_class');
                }
                else {
                    my $mutant_class_obj = CA::mutant_class->retrieve($mutant_class_id);
                    $mutant_class_hashref = caObj_to_hashref($mutant_class_obj, 'mutant_class')
                      if (defined $mutant_class_obj);
                }
                $mutant_class_id = $mutant_class_hashref->{mutant_id}
                  if (defined $mutant_class_hashref);

                if (!$mutant_class_id) {
                    my $max_mutant_class_id = &get_max_id('mutant_class_id', 'v2_mutant_class');
                    $mutant_class_id = $max_mutant_class_id + 1;

                    my $check = CA::mutant_class_edits->retrieve($mutant_class_id);
                    until (not defined $check) {
                        my $edits_max_mutant_class_id =
                          &get_max_id('mutant_class_id', 'v2_mutant_class_edits');
                        $mutant_class_id = $edits_max_mutant_class_id + 1;

                        $check = CA::mutant_class_edits->retrieve($mutant_class_id);
                    }
                }

                $save_edits{mutant_class} = 1;
            }

            $save_edits{mutant_info} = 1
              if ($mutant_hashref->{mutant_class_id} ne $mutant_class_id);

            $anno_ref->{mutant}->{$mutant_id}->{mutant_class_id} = $mutant_class_id;
            $anno_ref->{mutant_class}->{$mutant_class_id} =
              ($save_edits{mutant_class})
              ? $mutant_class_edits_hashref
              : $mutant_class_hashref;
        }
        else {
            my $tmp_mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};
            if ($tmp_mutant_id ne undef) {
                $anno_ref->{loci}->{$locus_id}->{mutant_id} = undef;
                $save_edits{loci} = 1;

                delete $anno_ref->{mutant}->{$tmp_mutant_id};

                my $tmp_mutant_class_id = $anno_ref->{mutant}->{$tmp_mutant_id}->{mutant_class_id};
                delete $anno_ref->{mutant_class}->{$tmp_mutant_class_id}
                  if (defined $tmp_mutant_class_id);
            }
        }

        $anno_ref->{loci}->{$locus_id}->{has_structural_annot} =
          $cgi->param('has_structural_annot');

        #save current value to db if save flag set
        if (defined $save_edits{loci}) {
            $anno_ref->{loci}->{$locus_id}->{mod_date} = &timestamp();
            my ($locus_edits_obj) = CA::loci_edits->retrieve(
                locus_id  => $locus_id,
                user_id   => $anno_ref->{'user_id'},
                family_id => $anno_ref->{'family_id'}
            );

            if (defined $locus_edits_obj) {
                $locus_edits_obj->set(edits => JSON::to_json($anno_ref->{loci}->{$locus_id}));
                $locus_edits_obj->update;
            }
            else {
                $locus_edits_obj = CA::loci_edits->insert(
                    {
                        locus_id  => $locus_id,
                        user_id   => $anno_ref->{user_id},
                        family_id => $anno_ref->{family_id},
                        edits     => JSON::to_json($anno_ref->{loci}->{$locus_id})
                    }
                );
            }

            $result{'mod_date'} = $anno_ref->{loci}->{$locus_id}->{mod_date};
        }

        if (defined $save_edits{mutant_info}) {
            $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};
            $anno_ref->{mutant}->{$mutant_id}->{mod_date} = &timestamp();
            my $mutant_edits_obj = CA::mutant_info_edits->retrieve($mutant_id);

            if (defined $mutant_edits_obj) {
                $mutant_edits_obj->set(
                    mutant_id => $mutant_id,
                    edits     => JSON::to_json($anno_ref->{mutant}->{$mutant_id})
                );
                $mutant_edits_obj->update;
            }
            else {
                $mutant_edits_obj = CA::mutant_info_edits->insert(
                    {
                        mutant_id => $mutant_id,
                        edits     => JSON::to_json($anno_ref->{mutant}->{$mutant_id})
                    }
                );
            }

            $result{'mutant_id'}       = $mutant_id;
            $result{'mutant_mod_date'} = $anno_ref->{mutant}->{$mutant_id}->{mod_date};
            $result{'has_alleles'}     = $anno_ref->{mutant}->{$mutant_id}->{has_alleles};
            $result{'updated_mutant'}  = 1;

            $mutant_class_id = $anno_ref->{mutant}->{$mutant_id}->{mutant_class_id};
            my $mutant_class_edits_obj = CA::mutant_class_edits->retrieve($mutant_class_id);

            if (defined $save_edits{mutant_class}) {
                if (defined $mutant_class_edits_obj) {
                    $mutant_class_edits_obj->set(
                        mutant_class_id => $mutant_class_id,
                        symbol          => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                        symbol_name     => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                    );
                }
                else {
                    $mutant_class_edits_obj = CA::mutant_class_edits->insert(
                        {
                            mutant_class_id => $mutant_class_id,
                            symbol          => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol},
                            symbol_name     => $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name}
                        }
                    );
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

        $result{'updated'} =
        (
                 defined $save_edits{loci}
              or defined $save_edits{mutant_info}
              or defined $save_edits{mutant_class}
          )
          ? 1 : undef;
          #? print "Update success! Changes submitted for administrator approval."
          #: print 'No changes to update.';

          print JSON::to_json( \%result );
    }
    else {

        #now output the session
        my $annotation_loop = [];
        my $row             = {};

        $row = $anno_ref->{loci}->{$locus_id};
        $row->{locus_id} = $locus_id;

        if (defined $anno_ref->{loci}->{$locus_id}->{mutant_id}
            and $anno_ref->{loci}->{$locus_id}->{mutant_id} ne "")
        {
            my $mutant_id = $anno_ref->{loci}->{$locus_id}->{mutant_id};

            $row->{mutant_id} = $mutant_id;
            my $mutant_class_id = $anno_ref->{mutant}->{$mutant_id}->{mutant_class_id};

            $row->{mutant_class_id}     = $mutant_class_id;
            $row->{mutant_class_symbol} = $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol};
            $row->{mutant_class_name} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol_name};

            $row->{mutant_phenotype} = $anno_ref->{mutant}->{$mutant_id}->{phenotype};

            $anno_ref->{mutant}->{$mutant_id}->{symbol} =
              $anno_ref->{mutant_class}->{$mutant_class_id}->{symbol}
              if ($anno_ref->{mutant}->{$mutant_id}->{symbol} eq "-");
            $row->{mutant_symbol}        = $anno_ref->{mutant}->{$mutant_id}->{symbol};
            $row->{mapping_data}         = $anno_ref->{mutant}->{$mutant_id}->{mapping_data};
            $row->{mutant_reference_lab} = $anno_ref->{mutant}->{$mutant_id}->{reference_lab};
            $row->{mutant_reference_pub} = $anno_ref->{mutant}->{$mutant_id}->{reference_pub};
            $row->{mutant_mod_date}      = $anno_ref->{mutant}->{$mutant_id}->{mod_date};

            $row->{has_alleles} = $anno_ref->{mutant}->{$mutant_id}->{has_alleles};
        }
        push(@$annotation_loop, $row);

        # HTML header
        print $session->header(-type => 'text/plain');

        $tmpl->param(annotation_loop => $annotation_loop);
        print $tmpl->output;
    }
}

sub delete_locus {
    my ($session, $cgi) = @_;
    my $anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    # EXECUTE THE QUERY
    my $locus_obj = CA::loci->retrieve(
        locus_id  => $locus_id,
        family_id => $anno_ref->{family_id},
        user_id   => $anno_ref->{user_id}
    );

    my $locus_edits_obj = CA::loci_edits->retrieve(
        locus_id  => $locus_id,
        family_id => $anno_ref->{family_id},
        user_id   => $anno_ref->{user_id}
    );

    if (defined $locus_edits_obj) {
        if (defined $locus_obj) {    # If locus_obj exists, just empty the 'edits' column
            $locus_edits_obj->edits("");
            $locus_edits_obj->update();
        }
        else {                       # else delete the edits object (since it is unapproved)
            $locus_edits_obj->delete();
        }
    }
    else {                           # otherwise, create a new edits_obj, with empty `edits` field
        $locus_edits_obj = CA::loci_edits->insert(
            {
                locus_id  => $locus_id,
                family_id => $anno_ref->{family_id},
                user_id   => $anno_ref->{user_id},
                edits     => ""
            }
        );
    }

    if (defined $locus_edits_obj) {
        delete $anno_ref->{loci}->{$locus_id};
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        print 'Deleted!';
    }
    else {
        print 'Error!';
    }
}

sub add_alleles {
    my ($session, $cgi) = @_;
    my $allele_list = $cgi->param('alleles_list');
    my $mutant_id   = $cgi->param('mutant_id');

    my $anno_ref = $session->param('anno_ref');

    $allele_list =~ s/^\s+|\s+$//;
    $allele_list =~ s/\s+/,/gs;

    my $allele_id;
    my @new_alleles = split(/,/, $allele_list);
    my $track = 0;
  ALLELE: for my $allele_name (@new_alleles) {
        my ($allele_obj) = CA::alleles->retrieve(
            allele_name => $allele_name,
            mutant_id   => $mutant_id
        );

        if (defined $allele_obj
            && exists $anno_ref->{allele}->{ $allele_obj->allele_id })
        {
            $allele_id = $allele_obj->allele_id;
            my $allele_edits_obj = CA::alleles_edits->retrieve(
                allele_id => $allele_id,
                mutant_id => $mutant_id
            );
            my $edits = $allele_edits_obj->edits if (defined $allele_edits_obj);

            if (defined $allele_edits_obj and $edits eq "") {
                $allele_edits_obj->delete;
                goto INSERT;
            }
            next ALLELE;
        }
        else {
            my $allele_edits_objs = CA::alleles_edits->retrieve_all();
            while (my $allele_edits_obj = $allele_edits_objs->next()) {
                my $allele_edits_hashref = JSON::from_json($allele_edits_obj->edits);

                next ALLELE
                  if ($allele_edits_hashref->{allele_name} eq $allele_name);
            }
        }

        if ($allele_id) {
            $allele_id += 1;
        }
        else {
            my $max_allele_id = &get_max_id('allele_id', 'v2_alleles');
            $allele_id = $max_allele_id + 1;

            my $check = CA::alleles_edits->retrieve(
                allele_id => $allele_id,
                mutant_id => $mutant_id
            );
            until (not defined $check) {
                my $edits_max_allele_id = &get_max_id('allele_id', 'v2_alleles_edits');
                $allele_id = $edits_max_allele_id + 1
                  if ($allele_id <= $edits_max_allele_id);

                $check = CA::alleles_edits->retrieve(
                    allele_id => $allele_id,
                    mutant_id => $mutant_id
                );
            }
        }

      INSERT:
        $anno_ref->{allele}->{$allele_id}->{mutant_id}         = $mutant_id;
        $anno_ref->{allele}->{$allele_id}->{allele_name}       = $allele_name;
        $anno_ref->{allele}->{$allele_id}->{alt_allele_names}  = q{};
        $anno_ref->{allele}->{$allele_id}->{reference_lab}     = q{};
        $anno_ref->{allele}->{$allele_id}->{altered_phenotype} = q{};

        my $new_allele_row = CA::alleles_edits->insert(
            {
                allele_id => $allele_id,
                mutant_id => $mutant_id,
                edits     => JSON::to_json($anno_ref->{allele}->{$allele_id})
            }
        );

        $track++;
    }

    $session->param('anno_ref', $anno_ref);
    $session->flush;

    print $session->header(-type => 'text/plain');

    #annotate($session, $cgi);
    print $track, ' allele', ($track > 2 or $track == 0) ? 's' : '', ' added!';
}

sub annotate_alleles {
    my ($session, $cgi, $save) = @_;
    my $tmpl      = HTML::Template->new(filename => "./tmpl/annotate_alleles.tmpl");
    my $anno_ref  = $session->param('anno_ref');
    my $user      = CA::users->retrieve($anno_ref->{user_id});
    my $mutant_id = $cgi->param('mutant_id');

    #save current value to db if save flag set
    my %save_edits = ();
    if ($save) {
        for my $allele_id (keys %{ $anno_ref->{allele} }) {
            my $track          = 0;
            my $allele_hashref = {};
            if (defined CA::alleles_edits->retrieve($allele_id)) {
                my $curr_allele_obj = CA::alleles_edits->retrieve(
                    allele_id => $allele_id,
                    mutant_id => $mutant_id,
                );
                $allele_hashref = JSON::from_json($curr_allele_obj->edits);
            }
            else {
                my $curr_allele_obj = CA::alleles->retrieve($allele_id);
                $allele_hashref = caObj_to_hashref($curr_allele_obj, 'alleles');
            }

            my $allele_edits_hashref = cgi_to_hashref($cgi, 'alleles', $allele_id);

            my @differences = data_diff($allele_hashref, $allele_edits_hashref);

            foreach my $diff (@differences) {
                $track = 1 if (defined $diff->{b});
            }

            $anno_ref->{mutant}->{$mutant_id}->{allele_id} = $allele_edits_hashref->{'allele_name'};
            $anno_ref->{allele}->{$allele_id} =
              ($track)
              ? $allele_edits_hashref
              : $allele_hashref;

            #save current value to db if save flag set
            if ($track) {
                my ($allele_edits_obj) = CA::alleles_edits->retrieve(
                    allele_id => $allele_id,
                    mutant_id => $mutant_id,
                );

                if (defined $allele_edits_obj) {
                    $allele_edits_obj->set(
                        mutant_id => $mutant_id,
                        edits     => JSON::to_json($anno_ref->{allele}->{$allele_id})
                    );
                    $allele_edits_obj->update;
                }
                else {
                    $allele_edits_obj = CA::alleles_edits->insert(
                        {
                            allele_id => $allele_id,
                            mutant_id => $mutant_id,
                            edits     => JSON::to_json($anno_ref->{allele}->{$allele_id})
                        }
                    );
                }
                $save_edits{alleles} = 1;
            }
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        # HTML header
        print $session->header(-type => 'text/plain');

        (defined $save_edits{alleles})
          ? print "Update success! Changes submitted for administrator approval."
          : print 'No changes to update.';
    }
    else {
        my $mutant_obj = CA::mutant_info->retrieve(mutant_id => $mutant_id);
        my $locus_obj       = CA::loci->retrieve(mutant_id => $mutant_id);
        my $mutant_symbol   = $mutant_obj->symbol;
        my $mutant_class_id = $mutant_obj->mutant_class_id;
        $mutant_symbol = fix_missing_mutant_symbol($mutant_symbol, $mutant_class_id)
          if ($mutant_obj->symbol eq "-" or $mutant_obj->symbol eq "");
        my $title = 'Annotate ' . $mutant_symbol . ' Alleles';

        my @annotated_alleles = CA::alleles->search(mutant_id => $mutant_id,);

        my @edited_alleles = CA::alleles_edits->search(mutant_id => $mutant_id,);

        my %all_alleles = ();
        $all_alleles{ $_->allele_id } = 1 foreach ((@annotated_alleles, @edited_alleles));

        foreach my $allele_id (sort { $a <=> $b } keys %all_alleles) {
            my $allele_edits_obj = CA::alleles_edits->retrieve(
                mutant_id => $mutant_id,
                allele_id => $allele_id,
            );

            my $allele_hashref = {};
            if (defined $allele_edits_obj) {
                my $edits = $allele_edits_obj->edits;
                next if ($edits eq "");    # allele has been deleted if $edits exists and is empty
                $allele_hashref = JSON::from_json($allele_edits_obj->edits);
            }
            else {
                my $allele_obj = CA::alleles->retrieve(
                    mutant_id => $mutant_id,
                    allele_id => $allele_id,
                );
                $allele_hashref = caObj_to_hashref($allele_obj, 'alleles') if(defined $allele_obj);
            }

            $anno_ref->{allele}->{$allele_id} = $allele_hashref;
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        #now output the session
        my $alleles_loop = [];
        my @allele_ids = sort { $a <=> $b } keys %{ $anno_ref->{allele} };
        for my $allele_id (@allele_ids) {
            next unless ( $anno_ref->{allele}->{$allele_id}->{mutant_id} == $mutant_id );

            my $row = {};

            $row->{allele_id}         = $allele_id;
            $row->{allele_name}       = $anno_ref->{allele}->{$allele_id}->{allele_name};
            $row->{alt_allele_names}  = $anno_ref->{allele}->{$allele_id}->{alt_allele_names};
            $row->{reference_lab}     = $anno_ref->{allele}->{$allele_id}->{reference_lab};
            $row->{altered_phenotype} = $anno_ref->{allele}->{$allele_id}->{altered_phenotype};
            push(@$alleles_loop, $row);
        }

        $tmpl->param(
            mutant_id    => $mutant_id,
            symbol       => $mutant_symbol,
            alleles_loop => $alleles_loop,
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
    my $allele_obj = CA::alleles->retrieve(
        allele_id => $allele_id,
        mutant_id => $mutant_id
    );

    my $allele_edits_obj = CA::alleles_edits->retrieve(
        allele_id => $allele_id,
        mutant_id => $mutant_id
    );

    if (defined $allele_edits_obj) {
        if (defined $allele_obj) {    # If allele_obj exists, just empty the 'edits' column
            $allele_edits_obj->edits("");
            $allele_edits_obj->update();
        }
        else {                        # else delete the edits object (since it is unapproved)
            $allele_edits_obj->delete();
        }
    }
    else {                            # otherwise, create a new edits_obj, with empty `edits` field
        $allele_edits_obj = CA::alleles_edits->insert(
            {
                allele_id => $allele_id,
                mutant_id => $mutant_id,
                edits     => ""
            }
        );
    }

    if (defined $allele_edits_obj) {
        delete $anno_ref->{allele}->{$allele_id};
        $session->param('anno_ref', $anno_ref);
        $session->flush;

        print 'Deleted!';
    }
    else {
        print 'Error!';
    }
}

sub structural_annotation {
    my ($session, $cgi) = @_;

    #my $locus_id = $cgi->param('locus_id');

    my $struct_anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $user        = CA::users->retrieve($struct_anno_ref->{user_id});
    my $family      = CA::family->retrieve($struct_anno_ref->{user_id});
    my ($locus_obj) = CA::loci->retrieve(
        user_id   => $struct_anno_ref->{user_id},
        family_id => $struct_anno_ref->{family_id},
        locus_id  => $locus_id
    );
    my $gene_locus  = $locus_obj->gene_locus;
    my $gene_symbol = $locus_obj->gene_symbol;

    my $ca_model_json = $cgi->param('model_json');
    my $tmpl = HTML::Template->new(filename => "./tmpl/structural_annotation.tmpl");

    my ($gff_locus_obj, $gene_models) = get_annotation_db_features($gene_locus, $gff_dbh);

    #when hooked into script - look for saved JSON in table if none passed as param
    #if no model JSON passed to script, create new from annotation gene model
    my ($ca_model_ds, $sa_object);
    if (!$ca_model_json) {    #JSON not passed as a parameter
        $sa_object = CA::structural_annot_edits->retrieve(locus_id => $locus_id);
        $sa_object = CA::structural_annot->retrieve(locus_id => $locus_id)
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
    my ($ca_model_feature) = create_ca_model_feature($ca_model_ds);
    my ($url, $map, $map_name) =
      create_ca_image_and_map($gff_dbh, $gff_locus_obj, $gene_models, $ca_model_feature);
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
    my $gene_locus      = $cgi->param('gene_locus');
    my $struct_anno_ref = $session->param('anno_ref');

    my %save_edits = ();
    my ($struct_locus_obj) = CA::loci->search(
        user_id    => $struct_anno_ref->{user_id},
        family_id  => $struct_anno_ref->{family_id},
        gene_locus => $gene_locus
    );
    my $struct_locus_id = $struct_locus_obj->locus_id;
    my $ca_model_json   = $cgi->param('model_json');

    #HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $model_obj = CA::structural_annot->retrieve(locus_id => $struct_locus_id);
    my $model_hashref = caObj_to_hashref($model_obj, 'structural_annot');
    my $sa_id = $model_obj->sa_id;

    my $model_edits_obj = CA::structural_annot_edits->retrieve(locus_id => $struct_locus_id);
    my $model_edits_hashref = caObj_to_hashref($model_edits_obj, 'structural_annot');

    my @differences = data_diff($model_hashref, $model_edits_hashref);

    foreach my $diff (@differences) {
        $save_edits{structural_annot} = 1 if (defined $diff->{b});
    }

    if (defined $save_edits{structural_annot}) {
        if (defined $model_edits_obj) {
            $model_edits_obj->model($ca_model_json);
            $model_edits_obj->update;
        }
        else {
            $model_edits_obj = CA::structural_annot_edits->insert(
                {
                    sa_id    => $sa_id,
                    locus_id => $struct_locus_id,
                    model    => $ca_model_json,
                }
            );
            $model_edits_obj->update;
        }
        print "Structure edits saved!";
    }
    else {
        print "No changes to save!";
    }

    $struct_anno_ref->{loci}->{$struct_locus_id}->{has_structural_annot} = 1;
    $session->param('anno_ref', $struct_anno_ref);
    $session->flush;
}

sub review_annotation {
    my ($session, $cgi) = @_;

    my $tmpl     = HTML::Template->new(filename => "./tmpl/review_annotation.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my $user     = CA::users->retrieve($anno_ref->{user_id});
    my $family   = CA::family->retrieve(family_id => $anno_ref->{family_id});

    my @annotated_loci = CA::loci->search(
        user_id   => $anno_ref->{user_id},
        family_id => $anno_ref->{family_id}
    );

    #print STDERR Dumper(@annotated_loci);

    my $review_loop = [];
    for my $locus (@annotated_loci) {
        my $row = {};
        $row->{locus_name}                = $locus->locus_name;
        $row->{original_annotation}       = $locus->original_annotation;
        $row->{gene_name}                 = $locus->gene_name;
        $row->{alt_gene_name}             = $locus->alt_gene_name;
        $row->{gene_description}          = $locus->gene_description;
        $row->{genbank_genomic_acc}       = $locus->genbank_genomic_acc;
        $row->{genbank_cdna_acc}          = $locus->genbank_cdna_acc;
        $row->{genbank_protein_acc}       = $locus->genbank_protein_acc;
        $row->{mutant_info}               = $locus->mutant_info;
        $row->{comment}                   = $locus->comment;
        $row->{has_structural_annotation} = $locus->has_structural_annotation;
        push(@$review_loop, $row);

    }
    $tmpl->param(review_loop => $review_loop, family_name => $family->name);
    print $session->header;

    #print $tmpl->output;
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub submit_annotation {
    my ($session, $cgi) = @_;
    my $tmpl     = HTML::Template->new(filename => "./tmpl/submit_annotation.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my $user     = CA::users->retrieve($anno_ref->{user_id});
    my $family   = CA::family->retrieve($anno_ref->{family_id});

    #print STDERR Dumper($family);
    $tmpl->param(family_name => $family->name);

    print $session->header;

    #print $tmpl->output;
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub final_submit {
    my ($session, $cgi) = @_;
    if ($cgi->param('submit_query') eq 'no') {
        annotate($session, $cgi);
        return;
    }
    my $tmpl     = HTML::Template->new(filename => "./tmpl/final_submit.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my $user     = CA::users->retrieve($anno_ref->{user_id});
    my $family   = CA::family->retrieve($anno_ref->{family_id});
    $tmpl->param(family_name => $family->name);
    print $session->header;

    #print $tmpl->output;
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

###################### Supporting subroutines #######################
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

        my ($description) = $hit->description;
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

sub get_family_info {
    my ($anno_ref, $family_id) = @_;
    my $family_obj = CA::family->retrieve($family_id);

    $anno_ref->{family_id}                                 = $family_id;
    $anno_ref->{family}->{$family_id}->{family_name}       = $family_obj->{family_name};
    $anno_ref->{family}->{$family_id}->{gene_class_symbol} = $family_obj->{gene_class_symbol};
    $anno_ref->{family}->{$family_id}->{description}       = $family_obj->{description};
    $anno_ref->{family}->{$family_id}->{source}            = $family_obj->{source};
    $anno_ref->{family}->{$family_id}->{is_public}         = $family_obj->{is_public};

    $session->param('anno_ref', $anno_ref);
    $session->flush;
}

sub get_user_info {
    my ($anno_ref, $user_id) = @_;
    my $user_obj = CA::users->retrieve($user_id);

    $anno_ref->{user_id}                             = $user_id;
    $anno_ref->{user}->{$user_id}->{username}        = $user_obj->username;
    $anno_ref->{user}->{$user_id}->{name}            = $user_obj->name;
    $anno_ref->{user}->{$user_id}->{email}           = $user_obj->email;
    $anno_ref->{user}->{$user_id}->{organization}    = $user_obj->organization;
    $anno_ref->{user}->{$user_id}->{url}             = $user_obj->url;
    $anno_ref->{user}->{$user_id}->{photo_file_name} = $user_obj->photo_file_name;

    $session->param('anno_ref', $anno_ref);
    $session->flush;
}

sub update_user_info {
    my ($anno_ref, $user_id) = @_;
    my $user_obj = CA::users->retrieve($user_id);

    $user_obj->set(
        username        => $anno_ref->{user}->{$user_id}->{username},
        name            => $anno_ref->{user}->{$user_id}->{name},
        email           => $anno_ref->{user}->{$user_id}->{email},
        organization    => $anno_ref->{user}->{$user_id}->{organization},
        url             => $anno_ref->{user}->{$user_id}->{url},
        photo_file_name => $anno_ref->{user}->{$user_id}->{photo_file_name}
    );
    $user_obj->update;
}

sub check_username {
    my ($user_id, $username) = @_;

    print $session->header(-type => 'text/plain');

    my $all_users = CA::users->retrieve_all();
    while (my $user = $all_users->next()) {
        next if ($user_id == $user->user_id);

        if ($username eq $user->username) {
            print "Taken!";
            exit;
        }
    }
    print "Available!";
}

sub caObj_to_hashref {
    my ($obj, $table_name) = @_;

    my %table_columns = (
        'loci' => [
            'gene_symbol',   'gene_locus',     'func_annotation', 'orig_func_annotation',
            'comment',       'gb_genomic_acc', 'gb_cdna_acc',     'gb_protein_acc',
            'reference_pub', 'mutant_id',      'mod_date',        'has_structural_annot'
        ],
        'mutant_info' => [
            'symbol',       'phenotype',       'reference_pub', 'reference_lab',
            'mapping_data', 'mutant_class_id'
        ],
        'mutant_class' => [ 'symbol', 'symbol_name' ],
        'alleles' =>
          [ 'mutant_id', 'allele_name', 'alt_allele_names', 'reference_lab', 'altered_phenotype' ]
    );

    my %hash;
    my @columns = @{ $table_columns{$table_name} };
    foreach my $column (@columns) {
        $hash{$column} = $obj->get($column);
    }

    return \%hash;
}

sub cgi_to_hashref {
    my ($cgi, $table_name, $id) = @_;

    ####### $cgi->parameter        => 'database_column_name' #######
    my %table_columns = (
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
            'has_alleles'          => 'has_alleles'
        },
        'mutant_class' => {
            'mutant_class_symbol' => 'symbol',
            'mutant_class_name'   => 'symbol_name',
        },
        'alleles' => {
            'mutant_id'             => "mutant_id",
            "allele_name_$id"       => "allele_name",
            "alt_allele_names_$id"  => "alt_allele_names",
            "reference_lab_$id"     => "reference_lab",
            "altered_phenotype_$id" => "altered_phenotype"
        }
    );

    my %hash;
    my %params = $cgi->Vars;
    foreach my $param (keys %params) {
        $hash{ $table_columns{$table_name}{$param} } = $params{$param}
          if (defined $table_columns{$table_name}{$param});
    }

    return \%hash;
}

sub fix_missing_mutant_symbol {

    # dirty hack to inherit the mutant_class_symbol for
    # mutant_info entries with no symbol or symbol eq "-"
    my ($mutant_symbol, $mutant_class_id) = @_;

    my $mutant_class_obj = CA::mutant_class->retrieve($mutant_class_id);
    $mutant_symbol = $mutant_class_obj->symbol;

    return $mutant_symbol;
}

sub get_loci {
    my ($cgi, $gene_locus) = @_;

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    # EXECUTE THE QUERY
    my @locus_feats = $gff_dbh->get_features_by_name(
        -name  => "$gene_locus*",
        -types => 'gene'
    );

    # LOOP THROUGH RESULTS
    my @query_output = ();
    foreach my $locus_obj (@locus_feats) {
        my $id = $locus_obj->name;
        $id =~ s/\D+//gs;
        push @query_output,
          {
            'id'                   => $id,
            'value'                => $locus_obj->name,
            'orig_func_annotation' => $locus_obj->notes
          };
    }
    @query_output = sort { $a->{id} <=> $b->{id} } @query_output;
    @query_output = (scalar @query_output >= 10) ? @query_output[ 0 .. 9 ] : @query_output;

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

sub get_mutant_info {
    my ($cgi, $mutant_sym) = @_;

    # HTTP HEADER
    print $session->header(-type => 'application/json');

    $mutant_sym =~ s/[0-9]+$//gs;
    my @mutant_feats = CA::mutant_class->search_like(
        symbol => "%$mutant_sym%",
        { order_by => 'mutant_class_id' }
    );

    my @query_output = ();

    # LOOP THROUGH RESULTS
    foreach my $mutant_class_obj (@mutant_feats) {
        my $mutant_objs =
          CA::mutant_info->search(mutant_class_id => $mutant_class_obj->mutant_class_id);

        while (my $mutant_obj = $mutant_objs->next) {
            my @mutant_allele_objs = CA::alleles->search(mutant_id => $mutant_obj->mutant_id);

            push @query_output,
              {
                'id'    => $mutant_obj->mutant_id,
                'value' => ($mutant_obj->symbol eq "-") ? $mutant_class_obj->symbol
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

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

sub get_max_id {
    my ($id_field, $db_table) = @_;
    my $max_id = 0;

    my $max_q   = "SELECT MAX($id_field) FROM $db_table;";
    my $max_sth = $ca_dbh->prepare($max_q);
    $max_sth->execute();

    while (my @data = $max_sth->fetchrow_array()) {
        $max_id = $data[0];
    }

    $max_sth->finish();

    return $max_id;
}

sub get_original_annotation {
    my ($locus) = @_;

    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $gff_dbh->get_features_by_name(-name => $locus, -types => 'gene');
    my ($notes) = $locus_feature_obj->notes if (defined $locus_feature_obj);

    (defined $notes) ? return $notes : return "";
}

sub filter_hit_name {

    #this has to be changes based on the defline of your proteome file
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
            && (($primary_tag =~ /utr/i) || ($primary_tag =~ /cds/i)));

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
    my ($gff_dbh, $locus_obj, $gene_models, $ca_model_feature) = @_;

    my ($l_end5, $l_end3) = get_ends_from_feature($locus_obj);
    my ($c_end5, $c_end3) = get_ends_from_feature($ca_model_feature);
    my ($end5,   $end3);
    if ($locus_obj->strand == 1) {
        $end5 = $c_end5 < $l_end5 ? $c_end5 : $l_end5;
        $end3 = $c_end3 > $l_end3 ? $c_end3 : $l_end3;
    }
    else {
        $end3 = $c_end5 > $l_end5 ? $c_end5 : $l_end5;
        $end5 = $c_end3 < $l_end3 ? $c_end3 : $l_end3;
    }

#flip will have to be dynamically controlled by the strand of the ca  model or the primary working model

    my $panel = Bio::Graphics::Panel->new(
        -length     => $locus_obj->length,
        -key_style  => 'between',
        -width      => 600,
        -pad_left   => 20,
        -pad_right  => 20,
        -pad_top    => 20,
        -pad_bottom => 20,
        -start      => $end5,
        -end        => $end3,
        -flip       => $locus_obj->strand == -1 ? 1 : 0,

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
            -strand => $locus_obj->strand,
        ),
        -bump            => 0,
        -double          => 1,
        -tick            => 2,
        -relative_coords => 1,

        -key => 'Rel Coords'
    );

    $panel->add_track(
        $locus_obj,
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
        $gene_models,
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
        $ca_model_feature,
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

=comment

sub annotate_mutants {
    my ($session, $cgi, $save, $blast_results) = @_;
    my $tmpl     = HTML::Template->new(filename => "./tmpl/annotate.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my $user     = CA::users->retrieve($anno_ref->{user_id});

#if block should run id coming from the select family page, otherwise should already be in the session.
    if ($cgi->param('family_id')) {
        $anno_ref->{family_id} = $cgi->param('family_id');
        $session->param('anno_ref', $anno_ref);
        $session->flush;
    }
    my $family = CA::family->retrieve($anno_ref->{family_id});
    my $title  = 'Annotate ' . $family->gene_class_symbol . ' Gene Family';

    #coming in from the select family action - the database is the most up to data source
    if ($action eq 'annotate') {
        my @annotated_loci = CA::loci->search(user_id => $anno_ref->{user_id}, family_id => $anno_ref->{family_id});
        for my $locus (@annotated_loci) {
            my $locus_id = $locus->locus_id;
            my @alleles = CA::alleles->search(locus_id => $locus_id);

            $anno_ref->{loci}->{$locus_id}->{gene_locus}           = $locus->gene_locus;
            $anno_ref->{loci}->{$locus_id}->{orig_func_annotation} = $locus->orig_func_annotation;
            $anno_ref->{loci}->{$locus_id}->{gene_symbol}          = $locus->gene_symbol;
            $anno_ref->{loci}->{$locus_id}->{func_annotation}      = $locus->func_annotation;
            $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc}       = $locus->gb_genomic_acc;
            $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc}          = $locus->gb_cdna_acc;
            $anno_ref->{loci}->{$locus_id}->{gb_protein_acc}       = $locus->gb_protein_acc;
            $anno_ref->{loci}->{$locus_id}->{mutant_phenotype}     = $locus->mutant_phenotype;
            $anno_ref->{loci}->{$locus_id}->{allelic_locus_id}     = $locus->allelic_locus_id;
            $anno_ref->{loci}->{$locus_id}->{num_alleles} = (scalar @alleles > 0) ? scalar @alleles : 0;
            $anno_ref->{loci}->{$locus_id}->{mapping_data}         = $locus->mapping_data;
            $anno_ref->{loci}->{$locus_id}->{reference_lab}        = $locus->reference_lab;
            $anno_ref->{loci}->{$locus_id}->{reference_pub}        = $locus->reference_pub;
            $anno_ref->{loci}->{$locus_id}->{mod_date}             = $locus->mod_date;
            $anno_ref->{loci}->{$locus_id}->{comment}              = $locus->comment;
            $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = $locus->has_structural_annot;

        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;
    }

#now session loaded - modify session with current values from form if not coming in from select family
    if ($action ne 'annotate') {
        for my $locus_id (keys %{ $anno_ref->{loci} }) {
            $anno_ref->{loci}->{$locus_id}->{gene_locus}  = $cgi->param('gene_locus_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{gene_symbol} = $cgi->param('gene_symbol_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{func_annotation} = $cgi->param('func_annotation_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc} = $cgi->param('gb_genomic_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc} = $cgi->param('gb_cdna_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{gb_protein_acc} = $cgi->param('gb_protein_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{mutant_phenotype} = $cgi->param('mutant_phenotype_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{allelic_locus_id} = $cgi->param('allelic_locus_id_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{mapping_data} = $cgi->param('mapping_data_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{reference_lab} = $cgi->param('reference_lab_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{reference_pub} = $cgi->param('reference_pub_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{mod_date} = $cgi->param('mod_date_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{comment}  = $cgi->param('comment_' . $locus_id);

#$anno_ref->{loci}->{$locus_id}->{has_structural_annot} = $cgi->param('has_structural_annot_' . $locus_id);
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;
    }

    #save current value to db if save flag set
    if ($save) {
        my @save_locus_ids = $cgi->param('toProcess');
        for my $locus_id (@save_locus_ids) {
            my $locus_obj = CA::loci->retrieve($locus_id);

            $anno_ref->{loci}->{$locus_id}->{orig_func_annotation} = get_original_annotation($anno_ref->{loci}->{$locus_id}->{gene_locus});

            $locus_obj->set(
                gene_locus           => $anno_ref->{loci}->{$locus_id}->{gene_locus},
                orig_func_annotation => $anno_ref->{loci}->{$locus_id}->{orig_func_annotation},
                gene_symbol          => $anno_ref->{loci}->{$locus_id}->{gene_symbol},
                func_annotation      => $anno_ref->{loci}->{$locus_id}->{func_annotation},
                gb_genomic_acc       => $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc},
                gb_cdna_acc          => $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc},
                gb_protein_acc       => $anno_ref->{loci}->{$locus_id}->{gb_protein_acc},
                mutant_phenotype     => $anno_ref->{loci}->{$locus_id}->{mutant_phenotype},
                allelic_locus_id     => $anno_ref->{loci}->{$locus_id}->{allelic_locus_id},
                mapping_data         => $anno_ref->{loci}->{$locus_id}->{mapping_data},
                reference_lab        => $anno_ref->{loci}->{$locus_id}->{reference_lab},
                reference_pub        => $anno_ref->{loci}->{$locus_id}->{reference_pub},
                mod_date             => $anno_ref->{loci}->{$locus_id}->{mod_date},
                comment              => $anno_ref->{loci}->{$locus_id}->{comment},
                has_structural_annot => $anno_ref->{loci}->{$locus_id}->{has_structural_annot}
            );
            $locus_obj->update;
        }
    }

    #now output the session
    my $annotation_loop = [];
    for my $locus_id (
        sort { $anno_ref->{loci}->{$a} <=> $anno_ref->{loci}->{$b} }
        keys(%{ $anno_ref->{loci} })
      )
    {
        my $row = {};
        $row->{locus_id}             = $locus_id;
        $row->{gene_locus}           = $anno_ref->{loci}->{$locus_id}->{gene_locus};
        $row->{orig_func_annotation} = $anno_ref->{loci}->{$locus_id}->{orig_func_annotation};
        $row->{gene_symbol}          = $anno_ref->{loci}->{$locus_id}->{gene_symbol};
        $row->{func_annotation}      = $anno_ref->{loci}->{$locus_id}->{func_annotation};
        $row->{gb_genomic_acc}       = $anno_ref->{loci}->{$locus_id}->{gb_genomic_acc};
        $row->{gb_cdna_acc}          = $anno_ref->{loci}->{$locus_id}->{gb_cdna_acc};
        $row->{gb_protein_acc}       = $anno_ref->{loci}->{$locus_id}->{gb_protein_acc};
        $row->{mutant_phenotype}     = $anno_ref->{loci}->{$locus_id}->{mutant_phenotype};
        $row->{num_alleles}          = $anno_ref->{loci}->{$locus_id}->{num_alleles};

        #$row->{allelic_locus_id}     = $anno_ref->{loci}->{$locus_id}->{allelic_locus_id};
        $row->{mapping_data}         = $anno_ref->{loci}->{$locus_id}->{mapping_data};
        $row->{reference_lab}        = $anno_ref->{loci}->{$locus_id}->{reference_lab};
        $row->{reference_pub}        = $anno_ref->{loci}->{$locus_id}->{reference_pub};
        $row->{mod_date}             = $anno_ref->{loci}->{$locus_id}->{mod_date};
        $row->{comment}              = $anno_ref->{loci}->{$locus_id}->{comment};
        $row->{has_structural_annot} = $anno_ref->{loci}->{$locus_id}->{has_structural_annot};
        push(@$annotation_loop, $row);
    }

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

    $tmpl->param(annotation_loop => $annotation_loop,);
    print $session->header;

    #print $tmpl->output;
    push @breadcrumb,
      (
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        { 'link' => '#', 'menu_name' => $title }
      );
    $jcvi_vars->{title} = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{page_header} = $family->family_name . ' Gene Family';
    $jcvi_vars->{top_menu} = [
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=select_family',
            'menu_name' => 'Select Family'
        },
        {
            'link'      => '/cgi-bin/medicago/eucap2/eucap.pl?action=logout',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}
=cut


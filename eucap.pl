#!/usr/local/bin/perl
# $Id: eucap.pl 539 2007-07-24 00:21:04Z hamilton $

use warnings;
use strict;
use CGI;
use CGI::Carp qw( fatalsToBrowser );
use CGI::Session;
use Authen::Passphrase::MD5Crypt;
use Template;
use HTML::Template;
use DBI;
use File::Temp;
use IO::String;
use JSON;
use Switch;

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
use CA::CDBI;
use CA::loci;
use CA::superfamily;
use CA::family;
use CA::users;
use CA::structural_annotation;

# JCVI template page variables from MedicagoWeb.pm
use MedicagoWeb
  qw/:DEFAULT $site $home_page $side_menu $contact_email $body_tmpl $two_column_fluid_width/;
my $title        = 'Medicago truncatula Genome Project :: Community Annotation';
my $project_name = 'Medicago truncatula Community Annotation Portal';
my @breadcrumb   = ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => 'EuCAP' });
my @stylesheets  = qw(/medicago/include/css/eucap.css);
my @javascripts =
  qw(/medicago/include/js/eucap.js /medicago/include/js/json.js /medicago/include/js/stayontop.js /medicago/include/js/sorttable.js http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js);

# Initialize JCVI template
my $jcvi_tt = Template->new({ ABSOLUTE => 1, });
my $jcvi_vars = {
    title        => $title,
    site         => $site,
    home_page    => $home_page,
    project_name => $project_name,
    side_menu    => $side_menu,
    breadcrumb   => \@breadcrumb,
    stylesheets  => \@stylesheets,
    javascripts  => \@javascripts,
};

#webserver path params
my $APACHE_DOC_ROOT    = $ENV{"DOCUMENT_ROOT"};
my $WEBSERVER_DOC_PATH = $APACHE_DOC_ROOT . "/medicago";
my $WEBSERVER_TEMP_REL = '/medicago/tmp';

#Config
my $PROTEOME_BLAST_DB  = $WEBSERVER_DOC_PATH . '/eucap/blast_dbs/Mt3.5v5_GenesProteinSeq_20111014.fa';
my $WEBSERVER_TEMP_DIR = $WEBSERVER_DOC_PATH . '/tmp/';
my $BLASTALL           = '/usr/local/bin/blastall';

#local GFF DB connection params
my $GFF_DB_ADAPTOR  = 'DBI::mysql';                                         #Bio DB SeqFeature Store
my $GFF_DB_HOST     = 'mysql51-dmz-pro';
#my $GFF_DB_NAME     = 'gbrowse_medicago35';
my $GFF_DB_NAME     = 'medtr_gbrowse2';
my $GFF_DB_DSN      = join(':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST));
my $GFF_DB_USERNAME = 'access';
my $GFF_DB_PASSWORD = 'access';

#local community annotation DB connection params
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql51-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';
my $CA_DB_PASSWORD = 'L0g!n2db';

#need this dbh for CGI::Session
my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD)
  or die("cannot connect to CA database:$!");

#need this db connection for base annotation data
#my $gff_db = Bio::DB::GFF->new(
my $gff_db = Bio::DB::SeqFeature::Store->new(
    -adaptor => $GFF_DB_ADAPTOR,
    -dsn     => $GFF_DB_DSN,
    -user    => $GFF_DB_USERNAME,
    -pass    => $GFF_DB_PASSWORD,
) or die("cannot access Bio::DB::SeqFeature::Store database");

CGI::Session->name("EuCAP_ID");
my $cgi = CGI->new;
my $session = CGI::Session->new("driver:MySQL", $cgi, { Handle => $dbh })
  or die(CGI::Session->errstr . "\n");
init($session, $cgi);
$session->flush;
unless ($session->param('~logged_in')) {
    login_page();
}
my $action = $cgi->param('action');

if ($action eq 'select_family') {
    select_family($session, $cgi);
}
elsif ($action eq 'annotate') {
    annotate($session, $cgi);
}
elsif ($action eq 'logout') {
    logout($session, $cgi);
}
elsif ($action eq 'add_loci') {
    add_loci($session, $cgi);
}
elsif ($action eq 'run_blast') {
    run_blast($session, $cgi);
}
elsif ($action eq 'delete_checked') {
    delete_checked($session, $cgi);
}
elsif ($action eq 'save_annotation') {
    annotate($session, $cgi, 1);    #1 = save flag
}
elsif ($action eq 'review_annotation') {
    review_annotation($session, $cgi);
}
elsif ($action eq 'struct_anno') {
    structural_annotation($session, $cgi);
}
elsif ($action eq 'submit_annotation') {
    submit_annotation($session, $cgi);
}
elsif ($action eq 'submit_struct_anno') {
    submit_structural_annotation($session, $cgi);
}
elsif ($action eq 'final_submit') {
    final_submit($session, $cgi);
}
else {

    #logged in and fall through the actions - then log out
    logout($session, $cgi);
}

$jcvi_tt->process($two_column_fluid_width, $jcvi_vars) || $jcvi_tt->error();

$dbh->disconnect if $dbh;

# EuCAP subroutines
sub init {
    my ($session, $cgi) = @_;
    if ($session->param('~logged_in')) {
        return 1;
    }
    unless ($cgi->param('action')) {
        login_page();
        $jcvi_tt->process($two_column_fluid_width, $jcvi_vars) || $jcvi_tt->error();
        exit;
    }
    my $username = $cgi->param('username');
    my $password = $cgi->param('password');
    my ($user) = CA::users->search(username => $username);
    if (!$user) {
        login_page(1, "User name not found. Please check and try again.");
        $jcvi_tt->process($two_column_fluid_width, $jcvi_vars) || $jcvi_tt->error();
        exit;
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
        $session->param('anno_ref', $anno_ref);
        return 1;
    }
    else {
        login_page(1, "Password does not match! Please check and try again.");
        $jcvi_tt->process($two_column_fluid_width, $jcvi_vars) || $jcvi_tt->error();
        exit;
    }
}

sub login_page {
    my ($is_error, $error_string) = @_;
    my $tmpl = HTML::Template->new(filename => "./tmpl/login.tmpl");
    if ($is_error) {
        $tmpl->param(error        => 1);
        $tmpl->param(error_string => $error_string);
    }
    print $session->header;

    #print $tmpl->output;
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
    my $title             = "Select Gene Family";
    my $tmpl              = HTML::Template->new(filename => "./tmpl/select_family.tmpl");
    my $anno_ref          = $session->param('anno_ref');
    my $user              = CA::users->retrieve($anno_ref->{user_id});
    my @fams              = CA::family->search(user_id => $anno_ref->{user_id});
    my $gene_family_radio = [];
    for my $fam (@fams) {
        my $row =
          { family_id => $fam->family_id, name => $fam->name, description => $fam->description };
        push(@$gene_family_radio, $row);
    }
    $tmpl->param(
        gene_family_radio => $gene_family_radio,
        name              => $user->name,
        organization      => $user->organization,
        email             => $user->email,
        url               => $user->url,
    );
    print $session->header;

    #print $tmpl->output;
    push @breadcrumb, ({ 'link' => '#', 'menu_name' => $title });
    $jcvi_vars->{title}       = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{page_header} = "Select Gene Family to Annotate";
    $jcvi_vars->{top_menu}    = [
        {
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub annotate {
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
    my $title  = 'Annotate ' . $family->name . ' Gene Family';

    #coming in from the select family action - the database is the most up to data source
    if ($action eq 'annotate') {
        my @annotated_loci =
          CA::loci->search(user_id => $anno_ref->{user_id}, family_id => $anno_ref->{family_id});
        for my $locus (@annotated_loci) {
            my $locus_id = $locus->locus_id;
            $anno_ref->{loci}->{$locus_id}->{locus_name}          = $locus->locus_name;
            $anno_ref->{loci}->{$locus_id}->{original_annotation} = $locus->original_annotation;
            $anno_ref->{loci}->{$locus_id}->{gene_name}           = $locus->gene_name;
            $anno_ref->{loci}->{$locus_id}->{alt_gene_name}       = $locus->alt_gene_name;
            $anno_ref->{loci}->{$locus_id}->{gene_description}    = $locus->gene_description;
            $anno_ref->{loci}->{$locus_id}->{genbank_genomic_acc} = $locus->genbank_genomic_acc;
            $anno_ref->{loci}->{$locus_id}->{genbank_cdna_acc}    = $locus->genbank_cdna_acc;
            $anno_ref->{loci}->{$locus_id}->{genbank_protein_acc} = $locus->genbank_protein_acc;
            $anno_ref->{loci}->{$locus_id}->{mutant_info}         = $locus->mutant_info;
            $anno_ref->{loci}->{$locus_id}->{comment}             = $locus->comment;
            $anno_ref->{loci}->{$locus_id}->{has_structural_annotation} =
              $locus->has_structural_annotation;

        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;
    }

#now session loaded - modify session with current values from form if not coming in from select family
    if ($action ne 'annotate') {
        for my $locus_id (keys %{ $anno_ref->{loci} }) {
            $anno_ref->{loci}->{$locus_id}->{gene_name} = $cgi->param('gene_name_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{alt_gene_name} =
              $cgi->param('alt_gene_name_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{gene_description} =
              $cgi->param('gene_description_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{genbank_genomic_acc} =
              $cgi->param('genbank_genomic_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{genbank_cdna_acc} =
              $cgi->param('genbank_cdna_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{genbank_protein_acc} =
              $cgi->param('genbank_protein_acc_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{mutant_info} = $cgi->param('mutant_info_' . $locus_id);
            $anno_ref->{loci}->{$locus_id}->{comment}     = $cgi->param('comment_' . $locus_id);

#$anno_ref->{loci}->{$locus_id}->{has_structural_annotation} =  $cgi->param('has_structural_annotation_'.$locus_id);
        }
        $session->param('anno_ref', $anno_ref);
        $session->flush;
    }

    #save current value to db if save flag set
    if ($save) {
        for my $locus_id (keys %{ $anno_ref->{loci} }) {
            my $locus_obj = CA::loci->retrieve($locus_id);
            $locus_obj->set(
                gene_name           => $anno_ref->{loci}->{$locus_id}->{gene_name},
                alt_gene_name       => $anno_ref->{loci}->{$locus_id}->{alt_gene_name},
                gene_description    => $anno_ref->{loci}->{$locus_id}->{gene_description},
                genbank_genomic_acc => $anno_ref->{loci}->{$locus_id}->{genbank_genomic_acc},
                genbank_cdna_acc    => $anno_ref->{loci}->{$locus_id}->{genbank_cdna_acc},
                genbank_protein_acc => $anno_ref->{loci}->{$locus_id}->{genbank_protein_acc},
                mutant_info         => $anno_ref->{loci}->{$locus_id}->{mutant_info},
                comment             => $anno_ref->{loci}->{$locus_id}->{comment},
                has_structural_annotation =>
                  $anno_ref->{loci}->{$locus_id}->{has_structural_annotation},
            );
            $locus_obj->update;
        }
    }

    #now output the session
    my $annotation_loop = [];
    for my $locus_id (sort {$anno_ref->{loci}->{$a} <=> $anno_ref->{loci}->{$b}} keys(%{ $anno_ref->{loci} })) {
        my $row = {};
        $row->{locus_id}            = $locus_id;
        $row->{locus_name}          = $anno_ref->{loci}->{$locus_id}->{locus_name};
        $row->{original_annotation} = $anno_ref->{loci}->{$locus_id}->{original_annotation};
        $row->{gene_name}           = $anno_ref->{loci}->{$locus_id}->{gene_name};
        $row->{alt_gene_name}       = $anno_ref->{loci}->{$locus_id}->{alt_gene_name};
        $row->{gene_description}    = $anno_ref->{loci}->{$locus_id}->{gene_description};
        $row->{genbank_genomic_acc} = $anno_ref->{loci}->{$locus_id}->{genbank_genomic_acc};
        $row->{genbank_cdna_acc}    = $anno_ref->{loci}->{$locus_id}->{genbank_cdna_acc};
        $row->{genbank_protein_acc} = $anno_ref->{loci}->{$locus_id}->{genbank_protein_acc};
        $row->{mutant_info}         = $anno_ref->{loci}->{$locus_id}->{mutant_info};
        $row->{comment}             = $anno_ref->{loci}->{$locus_id}->{comment};
        $row->{has_structural_annotation} =
          $anno_ref->{loci}->{$locus_id}->{has_structural_annotation};
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

    $tmpl->param(
        description     => $family->description,
        annotation_loop => $annotation_loop,
    );
    print $session->header;

    #print $tmpl->output;
    push @breadcrumb, ({ 'link' => '#', 'menu_name' => $title });
    $jcvi_vars->{title}       = "Medicago truncatula :: EuCAP :: $title";
    $jcvi_vars->{page_header} = 'Community Annotation for the ' . $family->name . ' Gene Family';
    $jcvi_vars->{top_menu}    = [
        {
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub run_blast {
    my ($session, $cgi) = @_;
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

        $blast_results->{hits}->{$hit_count}->{hit_name}        = filter_hit_name($hit->name);
        $blast_results->{hits}->{$hit_count}->{hit_description} = $hit->description;
        $blast_results->{hits}->{$hit_count}->{e_value}         = $hit->significance;
        $blast_results->{hits}->{$hit_count}->{score}           = $hit->raw_score;
        $blast_results->{hits}->{$hit_count}->{length}          = $hit->length;

    }

    annotate($session, $cgi, 0, $blast_results);

    return;
}

sub delete_checked {
    my ($session, $cgi) = @_;
    my @deleted_locus_ids = $cgi->param('delete');
    my $anno_ref          = $session->param('anno_ref');

    #delete from session and db and regenerate page
    for my $locus_id (@deleted_locus_ids) {
        delete $anno_ref->{loci}->{$locus_id};
        my $locus_obj = CA::loci->retrieve($locus_id);
        $locus_obj->delete;
    }
    $session->param('anno_ref', $anno_ref);
    $session->flush;
    annotate($session, $cgi);
    return;
}

sub add_loci {
    my ($session, $cgi) = @_;
    my $locus_list = $cgi->param('locus_list');
    $locus_list =~ s/^\s+//;
    $locus_list =~ s/\s+$//;
    $locus_list =~ s/\s+/\n/g;
    my @new_loci = split(/\n/, $locus_list);
    my $anno_ref = $session->param('anno_ref');
    for my $locus (@new_loci) {
        my ($locus_obj) = CA::loci->search(
            locus_name => $locus,
            user_id    => $anno_ref->{user_id},
            family_id  => $anno_ref->{family_id}
        );

        if ($locus_obj && exists $anno_ref->{loci}->{ $locus_obj->locus_id }) {
            next;
        }
        else {
            my $original_annotation = get_original_annotation($locus);

            my $new_locus_row = CA::loci->insert(
                {
                    locus_name                => $locus,
                    original_annotation       => $original_annotation,
                    user_id                   => $anno_ref->{user_id},
                    family_id                 => $anno_ref->{family_id},
                    gene_name                 => q{},
                    gene_description          => q{},
                    genbank_genomic_acc       => q{},
                    genbank_cdna_acc          => q{},
                    genbank_protein_acc       => q{},
                    mutant_info               => q{},
                    comment                   => q{},
                    has_structural_annotation => 0,
                }
            );
            my $locus_id = $new_locus_row->locus_id;
            $anno_ref->{loci}->{$locus_id}->{locus_name}                = $locus;
            $anno_ref->{loci}->{$locus_id}->{original_annotation}       = $original_annotation;
            $anno_ref->{loci}->{$locus_id}->{gene_name}                 = q{};
            $anno_ref->{loci}->{$locus_id}->{alt_gene_name}             = q{};
            $anno_ref->{loci}->{$locus_id}->{gene_description}          = q{};
            $anno_ref->{loci}->{$locus_id}->{genbank_genomic_acc}       = q{};
            $anno_ref->{loci}->{$locus_id}->{genbank_cdna_acc}          = q{};
            $anno_ref->{loci}->{$locus_id}->{genbank_protein_acc}       = q{};
            $anno_ref->{loci}->{$locus_id}->{mutant_info}               = q{};
            $anno_ref->{loci}->{$locus_id}->{comment}                   = q{};
            $anno_ref->{loci}->{$locus_id}->{has_structural_annotation} = 0;
        }
    }
    $session->param('anno_ref', $anno_ref);
    $session->flush;
    annotate($session, $cgi);
    return;
}

sub review_annotation {
    my ($session, $cgi) = @_;

    my $tmpl     = HTML::Template->new(filename => "./tmpl/review_annotation.tmpl");
    my $anno_ref = $session->param('anno_ref');
    my $user     = CA::users->retrieve($anno_ref->{user_id});
    my $family   = CA::family->retrieve(family_id => $anno_ref->{family_id});

    my @annotated_loci =
      CA::loci->search(user_id => $anno_ref->{user_id}, family_id => $anno_ref->{family_id});

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
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
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
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub get_original_annotation {
    my ($locus) = @_;

    #may have to change depending on your gff group name for the loci
    my ($locus_feature_obj) = $gff_db->get_feature_by_name('gene' => $locus);
    my ($notes) = $locus_feature_obj->notes;
    return $notes;
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

sub structural_annotation {
    my ($session, $cgi) = @_;
    my $locus = $cgi->param('locus');

    my $struct_anno_ref    = $session->param('anno_ref');
    my $user               = CA::users->retrieve($struct_anno_ref->{user_id});
    my ($struct_locus_obj) = CA::loci->search(
        user_id    => $struct_anno_ref->{user_id},
        family_id  => $struct_anno_ref->{family_id},
        locus_name => $locus
    );
    my $struct_locus_id = $struct_locus_obj->locus_id;

    my $ca_model_json = $cgi->param('model_json');
    my $tmpl = HTML::Template->new(filename => "./tmpl/structural_annotation.tmpl");
    my $gff_dbh = $gff_db;
#      get_database_handle($GFF_DB_ADAPTOR, $GFF_DB_DSN, $GFF_DB_USERNAME, $GFF_DB_PASSWORD)
#      or die;
    my ($locus_obj, $gene_models) = get_annotation_db_features($locus, $gff_dbh);

    #when hooked into script - look for saved JSON in table if none passed as param
    #if no model JSON passed to script, create new from annotation gene model
    my $ca_model_ds;
    if (!$ca_model_json) {    #JSON not passed as a parameter
        my ($sa_object) = CA::structural_annotation->search(locus_id => $struct_locus_id);

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
      create_ca_image_and_map($gff_dbh, $locus_obj, $gene_models, $ca_model_feature);
    $map = add_js_event_to_map($map, $gene_models->[0]);
    my $ca_anno_loop = generate_table($ca_model_ds);
    $tmpl->param(
        img_path     => $url,
        map_name     => $map_name,
        map          => $map,
        ca_anno_loop => $ca_anno_loop,
        locus        => $locus,
        locus_type   => $ca_model_ds->{type},
        locus_seq_id => $ca_model_ds->{seq_id},
        locus_start  => $ca_model_ds->{start},
        locus_stop   => $ca_model_ds->{stop},
        locus_strand => $ca_model_ds->{strand},

        #model_json => $ca_model_json,
    );
    print $session->header;

    #print $tmpl->output;
    $jcvi_vars->{top_menu} = [
        {
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
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
            'link' =>
'/cgi-bin/medicago/eucap/eucap.pl?action=logout" onmouseover="window.status=\'\';return true;',
            'menu_name' => 'Logout (<em>' . $user->username . '</em>)'
        }
    ];
    $jcvi_vars->{main_content} = $tmpl->output;
}

sub submit_structural_annotation {
    my ($session, $cgi) = @_;
    my $locus           = $cgi->param('locus');
    my $struct_anno_ref = $session->param('anno_ref');

    my ($struct_locus_obj) = CA::loci->search(
        user_id    => $struct_anno_ref->{user_id},
        family_id  => $struct_anno_ref->{family_id},
        locus_name => $locus
    );
    my $struct_locus_id = $struct_locus_obj->locus_id;
    my $ca_model_json   = $cgi->param('model_json');

    my ($model_obj) = CA::structural_annotation->search(locus_id => $struct_locus_id);
    if ($model_obj) {
        $model_obj->model($ca_model_json);
        $model_obj->update;
    }
    else {
        $model_obj = CA::structural_annotation->insert(
            { locus_id => $struct_locus_id, model => $ca_model_json, });
    }

    $struct_locus_obj->has_structural_annotation(1);
    $struct_locus_obj->update;
    $struct_anno_ref->{loci}->{$struct_locus_id}->{has_structural_annotation} = 1;
    $session->param('anno_ref', $struct_anno_ref);
    $session->flush;
    $struct_anno_ref = undef;
    $action          = 'annotate';
    annotate($session, $cgi);
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
        next unless (($primary_tag) && (($primary_tag =~ /utr/i) || ($primary_tag =~ /cds/i)));

        my $lr = $track2link{$track} ||=
          (defined $track->option('link') ? $track->option('link') : $linkrule);
        next unless $lr;

        my $tr =
          exists $track2title{$track}
          ? $track2title{$track}
          : $track2title{$track} ||=
          (defined $track->option('title') ? $track->option('title') : $titlerule);
        my $tgr =
          exists $track2target{$track}
          ? $track2target{$track}
          : $track2target{$track} ||=
          (defined $track->option('target') ? $track->option('target') : $targetrule);

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

sub get_database_handle {
    my ($adaptor, $dsn, $user, $password) = @_;
#    my $processed_transcript_aggregator = Bio::DB::GFF::Aggregator->new(
#        -method      => "processed_transcript",
#        -main_method => "mRNA",
#        -sub_parts   => [ "three_prime_UTR", "CDS", "five_prime_UTR" ]
#    );

    my $gff_db = Bio::DB::SeqFeature::Store->new(
        -adaptor    => $adaptor,
#        -aggregator => [$processed_transcript_aggregator],
        -dsn        => $dsn,
        -user       => $user,
        -pass       => $password,
    ) or die("cannot access Bio::DB::SeqFeature::Store database");
    return $gff_db;
}

sub get_annotation_db_features {
    my ($locus, $gff_dbh) = @_;

    my @locus_objs = $gff_dbh->get_features_by_alias($locus);
    my $locus_obj = shift @locus_objs;
    my ($end5, $end3) = get_ends_from_feature($locus_obj);
    my $seg = $gff_dbh->segment($locus_obj->refseq, $end5, $end3);
    my @gene_models =
      $seg->features('IMGAG:mRNA', -attributes => { 'Name' => $locus });

    #will have to sort the gene models
    return ($locus_obj, \@gene_models);
}

sub get_ends_from_feature {
    my ($locus_obj) = @_;

    my $end5 = $locus_obj->strand == 1 ? $locus_obj->start : $locus_obj->end;
    my $end3 = $locus_obj->strand == 1 ? $locus_obj->end : $locus_obj->start;

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
        -width      => 800,
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
        -glyph     => 'processed_transcript',
        -connector => 'solid',
        -label     => sub {
            my $feature = shift;
            my $note    = $feature->attributes('Note');
            if ($note eq "") {
                return $feature->attributes('Gene');
            }
            else {
                return $note;
            }
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
        -glyph        => 'processed_transcript',
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

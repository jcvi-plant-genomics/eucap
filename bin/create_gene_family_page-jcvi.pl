#!/usr/local/bin/perl
# $Id: create_gene_family_page-jcvi.pl 542 2007-07-24 18:25:31Z hamilton $

use strict;
use warnings;
use Data::Dumper;
use Template;
use HTML::Template;
use Switch;
use Getopt::Long;

use lib '../lib/';
use CA::CDBI;
use CA::loci;
use CA::users;
use CA::family;
use CA::superfamily;

#local community annotation DB connection params
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';
my $CA_DB_PASSWORD = 'L0g!n2db';

my $user_id   = q{};
my $family_id = q{};

GetOptions('user_id=i' => \$user_id, 'family_id=i' => \$family_id);
unless ($family_id && $user_id) { die "Usage: perl $0 --user_id --family_id\n"; }

my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD) or die;

my $user = CA::users->retrieve($user_id);
my ($family) = CA::family->search(user_id => $user_id, family_id => $family_id);
my ($superfamily) = CA::superfamily->search(user_id => $user_id);
my @locus_info = CA::loci->search(user_id => $user_id, family_id => $family_id);

my $family_members = [];
for my $locus (@locus_info) {
    my $cdna_link;
    if ($locus->genbank_cdna_acc) {
        $locus->genbank_cdna_acc =~ s/^\s+//;
        $locus->genbank_cdna_acc =~ s/\s+$//;
        $locus->genbank_cdna_acc =~ s/\s+//g;
        my @accs = split(/,/, $locus->genbank_cdna_acc);
        for my $acc (@accs) {
            my $link =
"<a href=\"http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=nucleotide&val=$acc\">$acc</a>, ";
            $cdna_link .= $link;
        }
        if (scalar(@accs) == 1) {
            $cdna_link =~ s/,//;
        }
        $cdna_link =~ s/, $//;
    }
    my $protein_link;
    if ($locus->genbank_protein_acc) {
        $locus->genbank_protein_acc =~ s/^\s+//;
        $locus->genbank_protein_acc =~ s/\s+$//;
        $locus->genbank_protein_acc =~ s/\s+//g;
        my @accs = split(/,/, $locus->genbank_protein_acc);
        for my $acc (@accs) {
            my $link =
"<a href=\"http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?db=protein&val=$acc\">$acc</a>, ";
            $protein_link .= $link;
        }
        if (scalar(@accs) == 1) {
            $protein_link =~ s/,//;
        }
        $protein_link =~ s/, $//;
    }

    #my $image_file = $locus->user_id."_".$locus->family_id."_".$_->[0].".png";
    my $image_file = $locus->user_id . "_" . $locus->family_id . "_" . $locus->locus_id . ".png";

    my $row = {
        locus         => $locus->locus_name,
        gene_name     => $locus->gene_name,
        alt_gene_name => $locus->alt_gene_name,
        gene_des      => $locus->gene_description,
        tigr_annot    => $locus->original_annotation,
        genomic_acc   => $locus->genbank_genomic_acc,
        cdna_acc      => $cdna_link,
        prot_acc      => $protein_link,
        mutant        => $locus->mutant_info,
        comment       => $locus->comment,
        struct_anno   => $locus->has_structural_annotation,
        image_file    => $image_file
    };
    push(@$family_members, $row);
}

my $tmpl = HTML::Template->new(filename => "gene_family_page_template-mod.tmpl");
$tmpl->param(    #superfamily => $superfamily->name || 0,
    gene_family    => $family->name,
    crit           => $family->criteria,
    source         => $family->source,
    first_name     => $user->name,
    email          => $user->email,
    org            => $user->organization,
    url            => $user->url,
    family_members => $family_members,
    footer         => $family->footer
);

my $main_content = $tmpl->output;

my $title = 'Medicago truncatula Community Annotation Project :: ' . $family->name . ' Gene Family';
my $site  = '<em>M. truncatula</em>';
my $project_name = '<em>Medicago truncatula</em> Community Annotation Project';
my $gbrowsedb    = "medicago_imgag";
my $blastdb      = "mtbe";
my $zone;

#my ($server) = `uname -a` =~ /(\w+)\.jcvi\.org/;
switch ($ENV{SERVER_NAME}) {
    case /dev/  { $zone = "-dev"; }
    case /test/ { $zone = "-test"; }
    else        { $zone = ""; }
}
my $side_menu   = &get_side_links();
my @breadcrumb  = ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => 'Gene Family' });
my $page_header = "Gene Family Page";

#print "Content-type: text/html\n\n";
my $tt            = Template->new({ ABSOLUTE => 1, });
my $template_file = '/opt/www/common/perl_templates/2_column_fixed_width.tpl';
my $vars          = {
    title        => $title,
    site         => $site,
    home_page    => '/cgi-bin/medicago/index.cgi',
    project_name => $project_name,
    side_menu    => $side_menu,
    main_content => $main_content,
    page_header  => $page_header,
    breadcrumb   => \@breadcrumb,
};

$tt->process($template_file, $vars) || $tt->error();
$dbh->disconnect;

sub get_side_links {
    my $file = "/opt/www/medicago/cgi-bin/medicago/medicago_links.txt";
    open(LINK, "<$file") || die "can't open $file\n";
    my @array      = <LINK>;
    my @side_menu2 = ();
    foreach my $line (@array) {
        chomp($line);
        next if (not $line or $line =~ /^\s*#/);
        if ($line =~ /\<.*\>/) {
            $line =~ s/\<ZONE\>/$zone/g;
            $line =~ s/\<BLASTDB\>/$blastdb/g;
            $line =~ s/\<DB\>/$gbrowsedb/g;
        }
        if ($line =~ /^\t/) {
            $line =~ s/^\t//;
            my ($name, $link) = split(/\t/, $line);
            push(@side_menu2, { 'class' => 'subA', 'link' => $link, 'menu_name' => $name });
        }
        else {
            my ($name, $link) = split(/\t/, $line);
            push(@side_menu2, { 'link' => $link, 'menu_name' => $name });
        }
    }

    return (\@side_menu2);
}

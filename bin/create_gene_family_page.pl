#!/usr/local/bin/perl
# $Id: create_gene_family_page.pl 542 2007-07-24 18:25:31Z hamilton $

use strict;
use warnings;
use HTML::Template;
use Getopt::Long;
use lib '../lib/';
use CA::CDBI;
use CA::loci;
use CA::users;
use CA::family;
use CA::superfamily;

my $user_id   = q{};
my $family_id = q{};

GetOptions('user_id=i' => \$user_id, 'family_id=i' => \$family_id);
unless ($family_id && $user_id) { die "Usage: perl $0 --user_id --family_id\n"; }

#local community annotation DB connection params
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';
my $CA_DB_PASSWORD = 'L0g!n2db';

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

my $tmpl = HTML::Template->new(filename => "gene_family_page_template.tmpl");
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

open(my $out, ">", "$user_id" . "_" . "$family_id.shtml") or die;
print $out $tmpl->output;
close($out);
$dbh->disconnect;

exit;

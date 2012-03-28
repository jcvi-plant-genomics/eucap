#!/usr/local/bin/perl
# $Id: insert_family.pl 543 2007-07-24 19:16:27Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# Accessory script for inserting new gene family in the community annotation database

use warnings;
use strict;

#use DBI;
use Getopt::Long;
use lib '../lib/';
use CA::CDBI;
use CA::family;

#local community annotation DB connection params
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';                                          # 'mtg_ca_user'
my $CA_DB_PASSWORD = 'L0g!n2db';                                          # 'will be generated soon'

my $user_id           = q{};
my $family_name       = q{};
my $gene_class_symbol = q{};
my $description       = q{};

GetOptions(
    "user_id=i"           => \$user_id,
    "family_name=s"       => \$family_name,
    "gene_class_symbol=s" => \$gene_class_symbol,
    "description=s"       => \$description,
) or die;

unless ($user_id && $family_name && $gene_class_symbol && $description) {
    die
"all options must be given.\nusage: $0 --user_id=<user_id> --family_name=\"<family_name>\" --gene_class_symbol=<gene_family_symbol> --description=\"<family_description>\"\n\n";
}

eval {
    my $new_family_row = CA::family->insert(
        {
            user_id           => $user_id,
            family_name       => $family_name,
            gene_class_symbol => $gene_class_symbol,
            description       => $description,
        }
    );
};

if ($@) {
    die "Error loading family into database. Make sure you have created a user first!!: $@\n\n";
}

=comment
my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD) or die;
my $sth = $dbh->prepare(
"INSERT INTO family (user_id, family_name, gene_class_symbol, description) VALUES (?, ?, ?, ?)"
) or die;
$sth->execute($user_id, $family_name, $gene_class_symbol, $description) or die;
$sth->finish;
$dbh->disconnect;
=cut

exit;

#!/usr/local/bin/perl
# EuCAP - Eukaryotic Community Annotation Package
# Accessory script for inserting new gene family in the community annotation database

# Set the perl5lib path variable
BEGIN {
    unshift @INC, '../', './lib';
}

use warnings;
use strict;
use Getopt::Long;
use CA::DBHelper;

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
    my $new_family_obj = do('insert', 'family',
        {
            user_id           => $user_id,
            family_name       => $family_name,
            gene_class_symbol => $gene_class_symbol,
            description       => $description,
        }
    )

};

die "Error loading family into database. Make sure you have created the user first!!: $@\n\n"; if ($@);

print "Family `$family_name` loaded successfully!\n";
exit;

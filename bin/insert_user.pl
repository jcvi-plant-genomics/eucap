#!/usr/local/bin/perl
# EuCAP - Eukaryotic Community Annotation Package
# Accessory script for inserting users in the community annotation database

# Set the perl5lib path variable
BEGIN {
    unshift @INC, '../', './lib';
}

use warnings;
use strict;
use Getopt::Long;
use Authen::Passphrase::MD5Crypt;
use CA::DBHelper;

my $name     = q{};
my $email    = q{};
my $username = q{};
my $password = q{};

GetOptions(
    "name=s"     => \$name,
    "email=s"    => \$email,
    "username=s" => \$username,
    "password=s" => \$password,
) or die;

unless ($name && $email && $username && $password) {
    die
"all options must be given.\nusage: $0 --name=<annotator_name> --email=<annotator_email> --username=<username> --password=<password>\n\n";
}

my $crypt_obj = Authen::Passphrase::MD5Crypt->new(salt_random => 1, passphrase => $password) or die;
my $salt      = $crypt_obj->salt;
my $hash      = $crypt_obj->hash_base64;

eval {
    my $new_user_row = do('insert', 'users', 
        {
            name     => $name,
            email    => $email,
            username => $username,
            salt     => $salt,
            hash     => $hash
        }
    );
};

die "Error loading user into database: $@\n\n"; if ($@);

warn "[debug] $username, $salt, $hash\n";
print "User `$username` added successfully!\n";
exit;

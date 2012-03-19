#!/usr/local/bin/perl
# $Id: insert_user.pl 543 2007-07-24 19:16:27Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# Accessory script for inserting users in the community annotation database

use warnings;
use strict;
#use DBI;
use Getopt::Long;
use Authen::Passphrase::MD5Crypt;
use lib '../lib/';
use CA::CDBI;
use CA::users;

#local community annotation DB connection params
my $CA_DB_NAME     = 'MTGCommunityAnnot';
my $CA_DB_HOST     = 'mysql-lan-pro';
my $CA_DB_DSN      = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));
my $CA_DB_USERNAME = 'vkrishna';                                          # 'mtg_ca_user'
my $CA_DB_PASSWORD = 'L0g!n2db';                                          # 'will be generated soon'

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

=comment
eval {
    my $new_user_row = CA::users->insert(
        {
            name     => $name,
            email    => $email,
            username => $username,
            salt     => $salt,
            hash     => $hash
        }
    );
};

if ($@) {
    die "Error loading user into database: $@\n\n";
}
=cut

print "$username, $salt, $hash\n";
=comment
my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD) or die;
my $sth       = $dbh->prepare(
    "insert into v2_users (name, email, username, salt, hash) values ( ?, ?, ?, ?, ? ) ")
  or die;
$sth->execute($name, $email, $username, $salt, $hash) or die;
$sth->finish;
$dbh->disconnect;
=cut

exit;

#!/usr/bin/perl
# $Id: insert_user.pl 543 2007-07-24 19:16:27Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# Accessory script for inserting users in the community annotation database

use warnings;
use strict;
use DBI;
use Getopt::Long;
use Authen::Passphrase::MD5Crypt;

#local community annotation DB connection params
my $CA_DB_NAME = 'community_annotation';
my $CA_DB_HOST = 'hamilton-lx';
my $CA_DB_DSN = join( ':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST ) );
my $CA_DB_USERNAME = 'access';
my $CA_DB_PASSWORD = 'access';

my $name = q{};
my $email = q{};
my $username = q{};
my $password = q{};

my $rv = GetOptions("name=s" => \$name,
					"email=s" => \$email,
					"username=s" => \$username,
					"password=s" => \$password,
					) or die;

unless ($name and $email and $username and $password) { die "all options must be given.\n"}
my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD) or die;
my $crypt_obj = Authen::Passphrase::MD5Crypt->new( salt_random => 1, passphrase=> $password ) or die;
my $salt = $crypt_obj->salt;
my $hash = $crypt_obj->hash_base64;
my $sth = $dbh->prepare("insert into users (name, email, username, salt, hash) values ( ?, ?, ?, ?, ? ) ") or die;												
$sth->execute($name, $email, $username, $salt, $hash) or die;
$sth->finish;
$dbh->disconnect;

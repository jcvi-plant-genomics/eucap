package AnnotDB::DB::CDBI;

use base 'Class::DBI::Sybase';
use strict;
use warnings;
use IO::File;

my ($dsn, $username, $password) = getConfig();

__PACKAGE__->connection($dsn, $username, $password);
__PACKAGE__->set_sql(getdate => "SELECT getdate()");
__PACKAGE__->set_sql(set_textsize => "SET textsize ?");

sub getConfig {
    my ($username, $password, $dbhost);

    # Read the eucap.ini configuration file
    my %cfg = ();
    tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

    #internal legacy annotation DB connection params
    my $GFF_DB_NAME = $cfg{'annotdb'}{'database'};
    my ($GFF_DB_USERNAME, $GFF_DB_PASSWORD, $GFF_DB_HOST) =
      ($cfg{'annotdb'}{'username'}, $cfg{'annotdb'}{'password'}, $cfg{'annotdb'}{'hostname'});
    return ("dbi:Sybase:server=$GFF_DB_HOST;database=$GFF_DB_NAME", $GFF_DB_USERNAME, $GFF_DB_PASSWORD);
}

1;
